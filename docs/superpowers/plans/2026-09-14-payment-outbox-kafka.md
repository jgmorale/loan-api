# Payment Registration and Outbox Kafka Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement idempotent external payment registration with a transactional outbox, asynchronous payment lifecycle processing, and a Kafka publisher/listener boundary.

**Architecture:** `RegisterPayment` creates a `Payment` in `created` state and an associated `OutboxEvent` inside one database transaction. `PaymentCreatedListener` validates the payment and delegates balance mutation to the existing `ApplyPayment` use case, while `OutboxPublisher` sends durable event rows through a Kafka adapter with at-least-once delivery semantics. Kafka remains behind small application interfaces so the Rails test suite can use fakes.

**Tech Stack:** Ruby 3.2, Rails 7.0, Active Record, PostgreSQL `jsonb`, Minitest, `ruby-kafka`.

**Spec:** [docs/superpowers/specs/2026-09-14-payment-outbox-kafka-design.md](../specs/2026-09-14-payment-outbox-kafka-design.md)

## Global Constraints

- The endpoint is `POST /v1/external/payments`.
- The request fields are `folio_id`, `loan_id`, and `amount`.
- `Payment` statuses are exactly `created`, `validated`, and `applied`.
- `(folio_id, loan_id)` is unique at the database level.
- Payment creation and its `payment.created` outbox row commit in the same transaction.
- A repeated identical request returns HTTP `200`; a new registration returns HTTP `201`; a conflicting amount returns HTTP `409`.
- `ApplyPayment` remains the balance mutation boundary and must not run during the HTTP registration request.
- Kafka delivery is at least once; consumers must tolerate duplicate events.
- Tests use fakes and do not require a Kafka broker.

---

### Task 1: Add Payment and Outbox Persistence

**Files:**
- Create: `db/migrate/20260914000002_create_payments.rb`
- Create: `db/migrate/20260914000003_create_outbox_events.rb`
- Create: `app/models/payment.rb`
- Create: `app/models/outbox_event.rb`
- Modify: `db/schema.rb` via `bin/rails db:migrate`
- Test: `test/models/payment_test.rb`
- Test: `test/models/outbox_event_test.rb`

**Interfaces:**
- Produces `Payment` with `belongs_to :loan`, statuses `created`, `validated`, `applied`, and decimal `amount`.
- Produces `OutboxEvent` with UUID `event_id`, `event_name`, aggregate metadata, JSON body, publication metadata, and timestamps.

- [ ] **Step 1: Write failing model tests**

```ruby
require "test_helper"

class PaymentTest < ActiveSupport::TestCase
  test "accepts the payment lifecycle statuses" do
    loan = Loan.create!(total: 1_000, status: "loan")

    %w[created validated applied].each do |status|
      payment = Payment.new(folio_id: 123, loan: loan, amount: 10, status: status)
      assert payment.valid?, "expected #{status} to be valid"
    end
  end

  test "requires a unique folio and loan pair" do
    loan = Loan.create!(total: 1_000, status: "loan")
    Payment.create!(folio_id: 123, loan: loan, amount: 10, status: "created")
    duplicate = Payment.new(folio_id: 123, loan: loan, amount: 20, status: "created")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:folio_id], "has already been taken"
  end
end
```

- [ ] **Step 2: Run the focused tests and confirm the expected missing-model failure**

Run: `bin/rails test test/models/payment_test.rb`
Expected: FAIL because `Payment` and its table do not exist.

- [ ] **Step 3: Add the migrations and model validations**

Create the payments table with `folio_id` bigint, `loan_id` foreign key, decimal `amount` with precision 15 and scale 2, status default `created`, timestamps, and a unique index on `[folio_id, loan_id]`. Create the outbox table with UUID `event_id`, `event_name`, `aggregate_type`, bigint `aggregate_id`, JSONB `body`, UTC `occurred_at`, nullable `published_at`, integer `attempts` default `0`, nullable text `last_error`, and timestamps. Add `Payment` validations for presence, positive amount, and inclusion in the three statuses; add `belongs_to :loan`. Add `OutboxEvent` validations for required event metadata and a unique index on `event_id`.

- [ ] **Step 4: Run the focused tests and schema migration**

Run: `bin/rails db:migrate && bin/rails test test/models/payment_test.rb test/models/outbox_event_test.rb`
Expected: PASS, with the generated schema containing both tables and their unique indexes.

- [ ] **Step 5: Keep the migration/schema changes as one reviewable persistence commit**

```bash
git add db/migrate app/models test/models db/schema.rb
git commit -m "feat: add payments and outbox persistence"
```

---

### Task 2: Implement the Domain Event and Transactional Registration Use Case

**Files:**
- Create: `app/events/payment_created.rb`
- Modify: `app/use_cases/register_payment.rb`
- Create: `test/events/payment_created_test.rb`
- Create: `test/use_cases/register_payment_test.rb`
- Create: `app/errors/payment_conflict_error.rb`
- Modify: `app/controllers/application_controller.rb` only if shared conflict rendering is needed

**Interfaces:**
- `PaymentCreated.new(payment).event_id`, `.event_name`, `.aggregate_type`, `.aggregate_id`, `.occurred_at`, and `.body` return event data.
- `RegisterPayment#call(folio_id:, loan_id:, amount:)` returns `[payment, created]`, where `created` is `true` for a new payment and `false` for an identical existing registration.
- `PaymentConflictError` represents an existing `(folio_id, loan_id)` with a different amount.

- [ ] **Step 1: Write the event and registration tests**

```ruby
require "test_helper"

class RegisterPaymentTest < ActiveSupport::TestCase
  setup do
    @loan = Loan.create!(total: 1_000, status: "loan")
    @use_case = RegisterPayment.new
  end

  test "creates a payment and its outbox event atomically" do
    payment, created = @use_case.call(folio_id: 123, loan_id: @loan.id, amount: 700)

    assert created
    assert_equal "created", payment.status
    event = OutboxEvent.find_by!(aggregate_id: payment.id)
    assert_equal "payment.created", event.event_name
    assert_equal payment.id, event.body.fetch("payment_id")
    assert_equal 1, OutboxEvent.count
  end

  test "returns the same payment without creating another event" do
    first, = @use_case.call(folio_id: 123, loan_id: @loan.id, amount: 700)
    second, created = @use_case.call(folio_id: 123, loan_id: @loan.id, amount: 700)

    assert_not created
    assert_equal first.id, second.id
    assert_equal 1, OutboxEvent.count
  end

  test "rejects an idempotency key reused with another amount" do
    @use_case.call(folio_id: 123, loan_id: @loan.id, amount: 700)

    assert_raises(PaymentConflictError) do
      @use_case.call(folio_id: 123, loan_id: @loan.id, amount: 600)
    end
  end
end
```

- [ ] **Step 2: Run the tests and confirm they fail because the event/use case is missing**

Run: `bin/rails test test/events/payment_created_test.rb test/use_cases/register_payment_test.rb`
Expected: FAIL with missing constant or missing registration behavior.

- [ ] **Step 3: Implement the event and transaction**

Build `PaymentCreated` from the persisted payment, generate one UUID at event construction, and stringify the JSON body keys. In `RegisterPayment`, validate the loan through `Loan.find`, first return an existing matching payment, raise `PaymentConflictError` for a different amount, then create the payment and outbox event in `Payment.transaction`. Rescue the unique-index race by reloading the existing row and applying the same identical/conflict comparison; never create a second outbox row. Use `BigDecimal` values consistently so amount comparison does not depend on string formatting.

- [ ] **Step 4: Run the focused tests and the existing payment tests**

Run: `bin/rails test test/events/payment_created_test.rb test/use_cases/register_payment_test.rb test/use_cases/apply_payment_test.rb`
Expected: PASS, including the existing concurrent `ApplyPayment` coverage.

- [ ] **Step 5: Keep the domain/event changes as one reviewable commit**

```bash
git add app/events app/use_cases app/errors test/events test/use_cases
 git commit -m "feat: register payments with transactional outbox events"
```

---

### Task 3: Expose the Versioned Registration Endpoint

**Files:**
- Create: `app/controllers/v1/external/payments_controller.rb`
- Modify: `config/routes.rb`
- Modify: `app/controllers/application_controller.rb`
- Create: `test/integration/external_payments_test.rb`

**Interfaces:**
- `V1::External::PaymentsController#create` calls `RegisterPayment#call` and returns the documented payment JSON.
- Route helper/path resolves to `POST /v1/external/payments`.

- [ ] **Step 1: Write failing request tests**

```ruby
require "test_helper"

class ExternalPaymentsTest < ActionDispatch::IntegrationTest
  setup do
    @loan = Loan.create!(total: 1_000, status: "loan")
  end

  test "registers a payment without changing the loan balance" do
    post "/v1/external/payments", params: { folio_id: 123, loan_id: @loan.id, amount: "700.00" }, as: :json

    assert_response :created
    assert_equal "created", response.parsed_body.fetch("payment").fetch("status")
    assert_equal 1_000, @loan.reload.total
  end

  test "returns 200 for an identical repeated registration" do
    payload = { folio_id: 123, loan_id: @loan.id, amount: "700.00" }
    post "/v1/external/payments", params: payload, as: :json
    post "/v1/external/payments", params: payload, as: :json

    assert_response :ok
    assert_equal 1, Payment.count
    assert_equal 1, OutboxEvent.count
  end
end
```

- [ ] **Step 2: Run the request tests and confirm the route/controller failure**

Run: `bin/rails test test/integration/external_payments_test.rb`
Expected: FAIL with routing or missing controller behavior.

- [ ] **Step 3: Implement the controller and route**

Add `namespace :v1 do; namespace :external do; resources :payments, only: :create; end; end`. Permit only `folio_id`, `loan_id`, and `amount`; parse IDs as positive integers and amount as finite `BigDecimal`; let `RegisterPayment` own loan and conflict semantics. Render `{ payment: ... }`, returning `:created` for `created == true` and `:ok` otherwise. Add `rescue_from PaymentConflictError` returning `{ result: "conflict", message: ... }` with HTTP `409`, and preserve existing error behavior.

- [ ] **Step 4: Run the focused integration tests and all existing tests**

Run: `bin/rails test test/integration/external_payments_test.rb test/integration/payment_applications_test.rb test/use_cases/apply_payment_test.rb`
Expected: PASS with no change to the existing payment-application API.

- [ ] **Step 5: Keep the HTTP contract changes as one reviewable commit**

```bash
git add config/routes.rb app/controllers app/errors test/integration
 git commit -m "feat: expose external payment registration endpoint"
```

---

### Task 4: Add the Idempotent Payment Created Listener

**Files:**
- Create: `app/listeners/payment_created_listener.rb`
- Create: `test/listeners/payment_created_listener_test.rb`
- Modify: `app/models/payment.rb` only if explicit transition methods are needed

**Interfaces:**
- `PaymentCreatedListener#call(event)` accepts an event hash with `event_id`, `aggregate_id`, and `body`, and returns the persisted payment.

- [ ] **Step 1: Write failing listener tests**

```ruby
require "test_helper"

class PaymentCreatedListenerTest < ActiveSupport::TestCase
  test "validates and applies a created payment once" do
    loan = Loan.create!(total: 1_000, status: "loan")
    payment = Payment.create!(folio_id: 123, loan: loan, amount: 700, status: "created")
    event = PaymentCreated.new(payment)

    result = PaymentCreatedListener.new.call(event)

    assert_equal "applied", result.reload.status
    assert_equal 300, loan.reload.total
    assert_equal 1, PaymentApplication.where(payment_id: payment.id).count
  end

  test "does not apply an already applied payment twice" do
    loan = Loan.create!(total: 1_000, status: "loan")
    payment = Payment.create!(folio_id: 123, loan: loan, amount: 700, status: "created")
    event = PaymentCreated.new(payment)
    PaymentCreatedListener.new.call(event)
    PaymentCreatedListener.new.call(event)

    assert_equal 300, loan.reload.total
    assert_equal 1, PaymentApplication.where(payment_id: payment.id).count
  end
end
```

- [ ] **Step 2: Run the listener tests and confirm the missing-listener failure**

Run: `bin/rails test test/listeners/payment_created_listener_test.rb`
Expected: FAIL because `PaymentCreatedListener` does not exist.

- [ ] **Step 3: Implement validation, transition, and delegation**

Load the payment by `aggregate_id`, return immediately for `applied`, validate the loan and amount for `created` or `validated`, transition `created` to `validated`, call `ApplyPayment`, then transition to `applied`. Keep the transition and application transactionally coordinated so a failed application leaves the payment retryable; a `validated` payment retries application on the next delivery. Do not use the event body as authoritative for mutable loan state; use the persisted payment and current loan row.

- [ ] **Step 4: Run listener, use-case, and integration tests**

Run: `bin/rails test test/listeners/payment_created_listener_test.rb test/use_cases test/integration`
Expected: PASS and no second balance mutation on duplicate delivery.

- [ ] **Step 5: Keep listener changes as one reviewable commit**

```bash
git add app/listeners test/listeners app/models/payment.rb
 git commit -m "feat: process payment created events idempotently"
```

---

### Task 5: Add the Outbox Publisher and Kafka Adapter

**Files:**
- Modify: `Gemfile`
- Modify: `Gemfile.lock` via `bundle install`
- Create: `app/publishers/outbox_publisher.rb`
- Create: `app/adapters/kafka_event_publisher.rb`
- Create: `config/initializers/kafka.rb`
- Modify: `config/environments/test.rb` only if test-safe configuration is required
- Create: `test/publishers/outbox_publisher_test.rb`
- Create: `test/adapters/kafka_event_publisher_test.rb`

**Interfaces:**
- `KafkaEventPublisher#publish(outbox_event)` sends the event and returns after broker acknowledgement.
- `OutboxPublisher#publish_pending(limit: 100)` claims unpublished events, delegates to the event publisher, marks success with `published_at`, and records failure metadata.

- [ ] **Step 1: Write failing publisher tests with a fake transport**

```ruby
require "test_helper"

class OutboxPublisherTest < ActiveSupport::TestCase
  test "marks an event published only after the transport succeeds" do
    event = OutboxEvent.create!(event_id: SecureRandom.uuid, event_name: "payment.created",
                                aggregate_type: "Payment", aggregate_id: 1,
                                body: { "payment_id" => 1 }, occurred_at: Time.current)
    publisher = Class.new do
      attr_reader :events
      def initialize
        @events = []
      end
      def publish(event)
        @events << event
      end
    end.new

    OutboxPublisher.new(event_publisher: publisher).publish_pending

    assert_not_nil event.reload.published_at
    assert_equal 1, publisher.events.length
  end
end
```

- [ ] **Step 2: Run publisher tests and confirm missing implementation/dependency failures**

Run: `bin/rails test test/publishers/outbox_publisher_test.rb test/adapters/kafka_event_publisher_test.rb`
Expected: FAIL because the publisher classes and Kafka dependency are absent.

- [ ] **Step 3: Add Kafka configuration and implement the adapter**

Add `ruby-kafka` to the Gemfile. Configure brokers from `KAFKA_BROKERS`, topic from `KAFKA_PAYMENTS_TOPIC` with a non-secret development default, and client id from Rails configuration. Serialize `event.body` as JSON, use `event.event_id` as the message key, and add event metadata as Kafka headers where the selected client API supports headers.

- [ ] **Step 4: Implement polling, locking, retry metadata, and success marking**

Select unpublished rows in a transaction with row locks or an equivalent claim strategy. Increment `attempts` before publication, call the injected publisher, set `published_at` on success, and set `last_error` on failure without deleting the row. Keep the default publisher injectable so tests never connect to Kafka.

- [ ] **Step 5: Run publisher, adapter, and full test suite**

Run: `bundle install && bin/rails test`
Expected: PASS with no Kafka broker required; adapter tests assert the exact topic, key, JSON payload, and metadata passed to the fake Kafka client.

- [ ] **Step 6: Keep messaging changes as one reviewable commit**

```bash
git add Gemfile Gemfile.lock app/publishers app/adapters config/initializers test/publishers test/adapters
git commit -m "feat: publish payment events through kafka outbox"
```

---

### Task 6: Document Operations and Perform Final Verification

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-09-14-payment-outbox-kafka-design.md` only if implementation decisions require clarification

**Interfaces:**
- Documentation describes the endpoint payload/response, payment lifecycle, outbox delivery semantics, required Kafka environment variables, and local test behavior.

- [ ] **Step 1: Write documentation verification expectations**

Confirm the README will include:

```text
POST /v1/external/payments
KAFKA_BROKERS=localhost:9092
KAFKA_PAYMENTS_TOPIC=payments
```

and explicitly state that registration is asynchronous and duplicate requests with the same `(folio_id, loan_id)` are idempotent.

- [ ] **Step 2: Update the README with the actual local commands**

Document `bin/rails db:prepare`, `bin/rails test`, the JSON request, HTTP status behavior, and the Kafka configuration variables. Do not claim a Kafka broker is needed for the test suite.

- [ ] **Step 3: Run final verification**

Run: `bin/rails db:prepare && bin/rails test`
Expected: exit code `0` with all tests passing.

Run: `git diff --check`
Expected: no whitespace errors.

Run: `git status --short`
Expected: only the intended implementation, test, migration, documentation, and plan/spec files are modified.

- [ ] **Step 4: Review requirements against the spec**

Verify the final diff covers the endpoint, payment fields and statuses, unique idempotency key, atomic outbox insert, event schema, Kafka key/metadata, listener idempotency, retry metadata, and tests without adding unrelated payment features.
