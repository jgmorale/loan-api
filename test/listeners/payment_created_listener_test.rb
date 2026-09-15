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