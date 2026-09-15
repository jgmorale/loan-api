# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...
## Loan API

## Setup

```bash
bundle install
export POSTGRES_PASSWORD='set-this-in-your-environment'
bin/rails db:prepare
```

## Register an external payment

```http
POST /v1/external/payments
Content-Type: application/json

{
	"folio_id": 12345,
	"loan_id": 7,
	"amount": "700.00"
}
```

A new registration returns `201` with status `created`. The loan balance is not
changed by this request. A repeated request with the same `(folio_id, loan_id)`
and amount returns `200` and does not create another payment or outbox event.
Reusing the pair with another amount returns `409`.

Payment processing is asynchronous:

```text
created -> validated -> applied
```

The registration transaction writes the payment and its `payment.created` event
to the outbox together. The outbox publisher delivers events to Kafka at least
once, using `event_id` as the message key. Consumers must tolerate duplicate
delivery.

## Kafka configuration

```bash
export KAFKA_BROKERS=localhost:9092
export KAFKA_PAYMENTS_TOPIC=payments
```

The publisher tracks `published_at`, `attempts`, and `last_error` so a failed
publication remains available for retry. The test suite uses fake transports and
does not require a Kafka broker.

## Tests

```bash
bin/rails test
```
