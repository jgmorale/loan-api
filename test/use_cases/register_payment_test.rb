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