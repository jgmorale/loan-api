# Use Case Container + State Machine Modules Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Memoize use case instances behind a `UseCaseContainer` (Dry::Container) instead of `.new`-ing them at every call site, and extract the `Payment` and `Loan` state machines into their own concern modules.

**Architecture:** A single `Dry::Container` (`UseCaseContainer`) registered in a Rails initializer holds memoized instances of use cases and adapters. Controllers/listeners resolve use cases from the container via a private method instead of instantiating them directly. `Payment` gets a new `Transitionable` concern (created → validated → applied); `Loan`'s existing inline `state_machine` moves unchanged into a `LoanTransitionable` concern.

**Tech Stack:** Ruby on Rails 7, Minitest, `dry-container`, `dry-auto_inject`, `state_machines` / `state_machines-activerecord` (all already in the Gemfile).

**Spec:** [docs/superpowers/specs/2026-09-14-use-case-container-and-state-machines-design.md](../specs/2026-09-14-use-case-container-and-state-machines-design.md)

## Global Constraints

- No new transitions/states beyond what's used today (no `rejected` state on `Payment`).
- `RegisterPayment`/`ApplyPayment` are registered as plain memoized instances in the container — they do NOT use `Dry::AutoInject` (they have no injectable dependencies today).
- No behavior change to `ApplyPayment`/`RegisterPayment` business logic.
- Run tests with `bin/rails test <path>`.

---

### Task 1: `UseCaseContainer` initializer

**Files:**
- Create: `config/initializers/01_use_case_container.rb`
- Test: `test/initializers/use_case_container_test.rb`

**Interfaces:**
- Produces: global constant `UseCaseContainer` (a `Dry::Container` instance) resolvable via `UseCaseContainer[:register_payment]`, `UseCaseContainer[:apply_payment]`, `UseCaseContainer[:kafka_event_publisher]`, `UseCaseContainer[:outbox_publisher]`. All four registrations are memoized (`memoize: true`), so repeated resolutions return the same object.

- [ ] **Step 1: Write the failing test**

Create `test/initializers/use_case_container_test.rb`:

```ruby
require "test_helper"

class UseCaseContainerTest < ActiveSupport::TestCase
  test "memoizes register_payment across resolutions" do
    assert_same UseCaseContainer[:register_payment], UseCaseContainer[:register_payment]
  end

  test "memoizes apply_payment across resolutions" do
    assert_same UseCaseContainer[:apply_payment], UseCaseContainer[:apply_payment]
  end

  test "memoizes kafka_event_publisher across resolutions" do
    assert_same UseCaseContainer[:kafka_event_publisher], UseCaseContainer[:kafka_event_publisher]
  end

  test "memoizes outbox_publisher across resolutions" do
    assert_same UseCaseContainer[:outbox_publisher], UseCaseContainer[:outbox_publisher]
  end

  test "register_payment resolves to a RegisterPayment instance" do
    assert_instance_of RegisterPayment, UseCaseContainer[:register_payment]
  end

  test "apply_payment resolves to an ApplyPayment instance" do
    assert_instance_of ApplyPayment, UseCaseContainer[:apply_payment]
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/initializers/use_case_container_test.rb`
Expected: FAIL with `NameError: uninitialized constant UseCaseContainerTest::UseCaseContainer` (or similar — `UseCaseContainer` doesn't exist yet).

- [ ] **Step 3: Write minimal implementation**

Create `config/initializers/01_use_case_container.rb`:

```ruby
require "dry-container"
require "dry-auto_inject"

UseCaseContainer = Dry::Container.new

UseCaseContainer.register(:kafka_event_publisher, memoize: true) { KafkaEventPublisher.new }

UseCaseContainer.register(:outbox_publisher, memoize: true) do
  OutboxPublisher.new(event_publisher: UseCaseContainer[:kafka_event_publisher])
end

UseCaseContainer.register(:register_payment, memoize: true) { RegisterPayment.new }

UseCaseContainer.register(:apply_payment, memoize: true) { ApplyPayment.new }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/initializers/use_case_container_test.rb`
Expected: PASS (6 runs, 0 failures)

- [ ] **Step 5: Commit**

```bash
git add config/initializers/01_use_case_container.rb test/initializers/use_case_container_test.rb
git commit -m "feat: add UseCaseContainer for memoized use case instances"
```

---

### Task 2: Resolve use cases from the container at call sites

**Files:**
- Modify: `app/controllers/v1/external/payments_controller.rb`
- Modify: `app/listeners/payment_created_listener.rb`
- Test: `test/controllers/v1/external/payments_controller_test.rb` (create)
- Test: `test/listeners/payment_created_listener_test.rb` (append)

**Interfaces:**
- Consumes: `UseCaseContainer[:register_payment]`, `UseCaseContainer[:apply_payment]` from Task 1.
- Produces: `V1::External::PaymentsController#register_payment` (private) and `PaymentCreatedListener#apply_payment` (private), both returning the memoized use case instance from the container.

- [ ] **Step 1: Write the failing tests**

Create `test/controllers/v1/external/payments_controller_test.rb`:

```ruby
require "test_helper"

class V1::External::PaymentsControllerTest < ActiveSupport::TestCase
  test "#register_payment resolves the memoized use case from the container" do
    controller = V1::External::PaymentsController.new

    assert_same UseCaseContainer[:register_payment], controller.send(:register_payment)
  end
end
```

Append to `test/listeners/payment_created_listener_test.rb` (inside the existing `PaymentCreatedListenerTest` class):

```ruby
  test "#apply_payment resolves the memoized use case from the container" do
    listener = PaymentCreatedListener.new

    assert_same UseCaseContainer[:apply_payment], listener.send(:apply_payment)
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/v1/external/payments_controller_test.rb test/listeners/payment_created_listener_test.rb`
Expected: FAIL — `NoMethodError: private method 'register_payment' not defined` (and same for `apply_payment`).

- [ ] **Step 3: Update the controller**

In `app/controllers/v1/external/payments_controller.rb`, replace:

```ruby
      def create
        payment, created = RegisterPayment.new.call(
          folio_id: integer_param(:folio_id),
          loan_id: integer_param(:loan_id),
          amount: amount_param
        )

        render json: { payment: payment_json(payment) }, status: created ? :created : :ok
      end

      private
```

with:

```ruby
      def create
        payment, created = register_payment.call(
          folio_id: integer_param(:folio_id),
          loan_id: integer_param(:loan_id),
          amount: amount_param
        )

        render json: { payment: payment_json(payment) }, status: created ? :created : :ok
      end

      private

      def register_payment
        UseCaseContainer[:register_payment]
      end
```

- [ ] **Step 4: Update the listener**

In `app/listeners/payment_created_listener.rb`, replace:

```ruby
      ApplyPayment.new.call(
        loan_id: payment.loan_id,
        payment_id: payment.id,
        amount: payment.amount
      )

      payment.update!(status: "applied")
    end

    payment.reload
  end

  private
```

with:

```ruby
      apply_payment.call(
        loan_id: payment.loan_id,
        payment_id: payment.id,
        amount: payment.amount
      )

      payment.update!(status: "applied")
    end

    payment.reload
  end

  private

  def apply_payment
    UseCaseContainer[:apply_payment]
  end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bin/rails test test/controllers/v1/external/payments_controller_test.rb test/listeners/payment_created_listener_test.rb test/integration/external_payments_test.rb`
Expected: PASS, no regressions.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/v1/external/payments_controller.rb app/listeners/payment_created_listener.rb test/controllers/v1/external/payments_controller_test.rb test/listeners/payment_created_listener_test.rb
git commit -m "refactor: resolve use cases from UseCaseContainer instead of .new"
```

---

### Task 3: `Transitionable` concern for `Payment`

**Files:**
- Create: `app/models/concerns/transitionable.rb`
- Modify: `app/models/payment.rb`
- Modify: `app/listeners/payment_created_listener.rb`
- Test: `test/models/payment_test.rb` (append)

**Interfaces:**
- Consumes: nothing new (uses `state_machines-activerecord`, already in Gemfile).
- Produces: `Payment#validate_payment!` (created → validated), `Payment#applied!` (validated → applied). Both raise `StateMachines::InvalidTransition` when the current state doesn't allow the transition.

- [ ] **Step 1: Write the failing tests**

Append to `test/models/payment_test.rb` (inside `PaymentTest`):

```ruby
  test "transitions from created to validated to applied" do
    loan = Loan.create!(total: 1_000, status: "loan")
    payment = Payment.create!(folio_id: 123, loan: loan, amount: 10, status: "created")

    payment.validate_payment!
    assert_equal "validated", payment.reload.status

    payment.applied!
    assert_equal "applied", payment.reload.status
  end

  test "does not allow applying a payment that has not been validated" do
    loan = Loan.create!(total: 1_000, status: "loan")
    payment = Payment.create!(folio_id: 123, loan: loan, amount: 10, status: "created")

    assert_raises(StateMachines::InvalidTransition) { payment.applied! }
    assert_equal "created", payment.reload.status
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/payment_test.rb`
Expected: FAIL with `NoMethodError: undefined method 'validate_payment!' for #<Payment...>`.

- [ ] **Step 3: Create the concern**

Create `app/models/concerns/transitionable.rb`:

```ruby
module Transitionable
  extend ActiveSupport::Concern

  included do
    state_machine :status, initial: :created, use_transactions: false do
      event :validate_payment do
        transition created: :validated
      end

      event :apply do
        transition validated: :applied
      end
    end
  end
end
```

- [ ] **Step 4: Update the `Payment` model**

Replace the full contents of `app/models/payment.rb`:

```ruby
class Payment < ApplicationRecord
  include Transitionable

  belongs_to :loan

  validates :folio_id, :amount, presence: true
  validates :folio_id, uniqueness: { scope: :loan_id }
  validates :amount, numericality: { greater_than: 0 }
end
```

- [ ] **Step 5: Update the listener to use state machine events**

In `app/listeners/payment_created_listener.rb`, replace:

```ruby
    Payment.transaction do
      loan = payment.loan
      validate_payment!(payment, loan)
      payment.update!(status: "validated") if payment.status == "created"

      apply_payment.call(
        loan_id: payment.loan_id,
        payment_id: payment.id,
        amount: payment.amount
      )

      payment.update!(status: "applied")
    end
```

with:

```ruby
    Payment.transaction do
      loan = payment.loan
      validate_payment!(payment, loan)
      payment.validate_payment! if payment.status == "created"

      apply_payment.call(
        loan_id: payment.loan_id,
        payment_id: payment.id,
        amount: payment.amount
      )

      payment.applied!
    end
```

(`validate_payment!(payment, loan)` — the pre-existing private amount-validation method — keeps its name; only the state machine transition calls change. Ruby resolves `payment.validate_payment!` against the `Payment` instance and the bare `validate_payment!(payment, loan)` against the listener's own private method, so there's no naming collision.)

- [ ] **Step 6: Run tests to verify they pass**

Run: `bin/rails test test/models/payment_test.rb test/listeners/payment_created_listener_test.rb test/integration/external_payments_test.rb test/integration/payment_applications_test.rb`
Expected: PASS, no regressions.

- [ ] **Step 7: Commit**

```bash
git add app/models/concerns/transitionable.rb app/models/payment.rb app/listeners/payment_created_listener.rb test/models/payment_test.rb
git commit -m "feat: extract Payment state machine into Transitionable concern"
```

---

### Task 4: `LoanTransitionable` concern for `Loan`

**Files:**
- Create: `app/models/concerns/loan_transitionable.rb`
- Modify: `app/models/loan.rb`

**Interfaces:**
- Produces: `Loan#paid!` (unchanged behavior — `[:loan, :disbursed] => :paid`), moved out of the model into `LoanTransitionable`.

- [ ] **Step 1: Write the failing test**

Add to `test/models/` a new file `test/models/loan_test.rb`:

```ruby
require "test_helper"

class LoanTest < ActiveSupport::TestCase
  test "transitions from loan to paid" do
    loan = Loan.create!(total: 1_000, status: "loan")

    loan.paid!(run_action: false)

    assert_equal "paid", loan.status
  end

  test "does not allow transitioning to paid from created" do
    loan = Loan.create!(total: 1_000, status: "created")

    assert_raises(StateMachines::InvalidTransition) { loan.paid!(run_action: false) }
  end
end
```

- [ ] **Step 2: Run test to verify it passes already (baseline)**

Run: `bin/rails test test/models/loan_test.rb`
Expected: PASS — this test documents existing behavior before the refactor, so it should already pass since `Loan`'s `state_machine` is unchanged so far. This confirms the baseline before moving the code.

- [ ] **Step 3: Create the concern**

Create `app/models/concerns/loan_transitionable.rb`:

```ruby
module LoanTransitionable
  extend ActiveSupport::Concern

  included do
    state_machine :status, initial: :created do
      state :loan
      state :created
      state :approved
      state :disbursed
      state :paid

      event :paid do
        transition [:loan, :disbursed] => :paid
      end
    end
  end
end
```

- [ ] **Step 4: Update the `Loan` model**

Replace the full contents of `app/models/loan.rb`:

```ruby
class Loan < ApplicationRecord
  include LoanTransitionable

  has_many :payment_applications, dependent: :restrict_with_exception
end
```

- [ ] **Step 5: Run tests to verify nothing broke**

Run: `bin/rails test test/models/loan_test.rb test/use_cases/apply_payment_test.rb test/listeners/payment_created_listener_test.rb test/integration/payment_applications_test.rb`
Expected: PASS, no regressions.

- [ ] **Step 6: Commit**

```bash
git add app/models/concerns/loan_transitionable.rb app/models/loan.rb test/models/loan_test.rb
git commit -m "refactor: move Loan state machine into LoanTransitionable concern"
```

---

### Task 5: Full regression run

**Files:** none (verification-only task)

- [ ] **Step 1: Run the full test suite**

Run: `bin/rails test`
Expected: PASS, 0 failures, 0 errors.

- [ ] **Step 2: Confirm no leftover references to the old pattern**

Run: `grep -rn "RegisterPayment.new\|ApplyPayment.new" app/`
Expected: no matches (both call sites now resolve through `UseCaseContainer`).
