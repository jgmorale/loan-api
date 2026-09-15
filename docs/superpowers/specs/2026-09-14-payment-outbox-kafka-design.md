# Payment Registration and Outbox Design

**Date:** 2026-09-14

## Goal

Add an idempotent external payment registration flow that records a payment and its `payment.created` domain event atomically, then supports asynchronous validation, loan application, and reliable Kafka publication through an outbox.

## Current Context

The Rails API already has:

- `Loan`, with a state machine and a decimal remaining balance stored in `total`.
- `PaymentApplication`, uniquely scoped by `loan_id` and `payment_id`.
- `ApplyPayment`, which locks the loan, prevents duplicate applications, updates the balance, and marks a fully paid loan.
- No `Payment` entity, outbox table, Kafka adapter, or versioned external payment route.

The new registration flow must not move the existing balance mutation into the HTTP request. It should reuse `ApplyPayment` when the asynchronous listener applies a validated payment.

## Functional Design

### HTTP registration

Add `POST /v1/external/payments` with JSON body:

```json
{
  "folio_id": 12345,
  "loan_id": 7,
  "amount": "700.00"
}
```

The endpoint will:

1. Parse and validate the required fields.
2. Create a `Payment` with status `created`.
3. Create one `OutboxEvent` for the `payment.created` domain event.
4. Commit both rows in one database transaction.
5. Return HTTP `201` with the registered payment representation.

The response must include the payment identifier, `folio_id`, `loan_id`, `amount`, `status`, and `created_at`. The endpoint must not apply the loan balance synchronously.

### Idempotency

`Payment` has a unique database index on `(folio_id, loan_id)`. A repeated request with the same pair returns the existing payment and does not insert another outbox event. The database constraint is authoritative, so concurrent requests cannot create two registrations. The use case must handle the uniqueness race by retrieving the row created by the competing transaction.

A repeated request with the same `(folio_id, loan_id)` but a different amount is rejected as a conflict; it must never mutate the existing payment or create another event. The implementation should expose this as a domain-level conflict error so the controller returns HTTP `409`.

### Payment lifecycle

The available statuses are exactly:

- `created`: registered and waiting for asynchronous validation.
- `validated`: validation succeeded and the payment is ready to be applied.
- `applied`: `ApplyPayment` completed successfully.

State changes must be explicit and reject invalid transitions. Validation checks that the loan exists and the amount is positive and does not exceed the current loan balance. Applying a payment uses the existing `ApplyPayment` use case with `payment.id` as its `payment_id`, so the current loan lock and application idempotency remain the source of truth for balance mutation.

The listener must be idempotent:

- A duplicate `payment.created` event for an `applied` payment is acknowledged without repeating work; an event for a `validated` payment may retry application.
- A payment already `applied` must never change the loan balance again.
- A failed validation or application must leave enough persisted state/logging for retry handling without falsely marking the payment `applied`.

## Domain Event and Outbox

Define a `PaymentCreated` domain event with:

- `event_id`: UUID generated once when the event is created.
- `event_name`: `payment.created`.
- `occurred_at`: UTC timestamp.
- `aggregate_type`: `Payment`.
- `aggregate_id`: the payment primary key.
- `body`: JSON object containing `payment_id`, `folio_id`, `loan_id`, `amount`, `status`, and `created_at`.

`OutboxEvent` persists those fields plus delivery metadata:

- `published_at`: nullable UTC timestamp set only after Kafka acknowledges publication.
- `attempts`: integer defaulting to zero.
- `last_error`: nullable text containing the latest publish failure.
- `created_at` and `updated_at`.

`body` should use PostgreSQL `jsonb` in production. The outbox row and payment row must be written in the same `ActiveRecord.transaction`; if either write fails, neither is committed.

The outbox publisher will select unpublished events, publish them, and mark them published only after broker acknowledgement. It must support retries and avoid deleting rows immediately, so publication history and replay remain possible. Selection must be safe for concurrent publisher workers, using row locking/claiming or an equivalent database strategy.

## Kafka Boundary

Keep Kafka behind an application port and infrastructure adapter:

- The application-facing publisher accepts an `OutboxEvent` and returns success or raises a publish error.
- The Kafka adapter serializes `body` as JSON, uses `event_id` as the Kafka message key, and emits `event_name`, `aggregate_type`, and `occurred_at` as headers or equivalent metadata.
- Topic name and broker configuration come from Rails environment configuration, not hard-coded business logic.
- Delivery semantics are at least once. Consumers must deduplicate by `event_id` or by the payment lifecycle state.
- The local test suite must use a fake publisher; a real Kafka broker is not required for unit/integration tests.

## Listener Boundary

Define a listener/consumer for `payment.created` that:

1. Deserializes and validates the event body.
2. Loads the payment by `aggregate_id`/`payment_id`.
3. Validates the payment and transitions `created` to `validated`.
4. Calls `ApplyPayment` with `loan_id: payment.loan_id`, `payment_id: payment.id`, and `amount: payment.amount`.
5. Transitions the payment to `applied` after successful application.
6. Acknowledges duplicate or already-applied events without repeating the balance mutation.

The listener should keep transport acknowledgement separate from domain processing: acknowledge only after successful processing or after a deliberate retry/dead-letter decision.

## Error Handling

- Missing or malformed request fields return HTTP `400`.
- Unknown loan, invalid amount, and amount greater than the current balance follow the existing bad-request error style unless the plan introduces a more precise domain error.
- Duplicate folio/loan with identical data returns the original registration with HTTP `200`; a newly-created registration returns HTTP `201`.
- Duplicate folio/loan with conflicting amount returns HTTP `409`.
- Database transaction failures return the framework's normal server error and must not leave a payment without its outbox event.
- Kafka failures do not roll back a committed registration; the unpublished outbox row is retried.

## Testing Requirements

Cover at minimum:

- Payment model fields, allowed statuses, required values, foreign key, and unique `(folio_id, loan_id)` constraint.
- Registration use case creates payment and outbox event atomically.
- Registration returns the existing payment without duplicating the event.
- Concurrent duplicate registrations result in one payment and one outbox event.
- Conflicting duplicate input returns a conflict and leaves the original unchanged.
- HTTP contract for `201`, idempotent repeat, malformed input, and unknown loan.
- Listener transitions `created` to `validated` to `applied` and invokes `ApplyPayment` once.
- Duplicate listener delivery does not apply the balance twice.
- Outbox publisher marks an event published only after successful Kafka acknowledgement and records retry metadata on failure.
- Event serialization includes the stable key and metadata required by Kafka consumers.

## Non-Goals

- Do not introduce a Kafka broker into the test environment.
- Do not redesign the existing `ApplyPayment` balance algorithm.
- Do not add unrelated payment query endpoints, refunds, cancellation, or dead-letter infrastructure beyond the minimum retry boundary needed by the publisher/listener contracts.
