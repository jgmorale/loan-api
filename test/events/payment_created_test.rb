require "test_helper"

class PaymentCreatedTest < ActiveSupport::TestCase
  test "contains stable payment event metadata and body" do
    loan = Loan.create!(total: 1_000, status: "loan")
    payment = Payment.create!(folio_id: 123, loan: loan, amount: 700, status: "created")

    event = PaymentCreated.new(payment)

    assert_equal "payment.created", event.event_name
    assert_equal "Payment", event.aggregate_type
    assert_equal payment.id, event.aggregate_id
    assert_match(/\A[0-9a-f-]{36}\z/, event.event_id)
    assert_equal payment.id, event.body.fetch("payment_id")
    assert_equal payment.loan_id, event.body.fetch("loan_id")
    assert_equal "created", event.body.fetch("status")
  end
end
