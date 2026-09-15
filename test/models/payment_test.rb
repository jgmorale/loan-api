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

  test "transitions from created to validated to applied" do
    loan = Loan.create!(total: 1_000, status: "loan")
    payment = Payment.create!(folio_id: 123, loan: loan, amount: 10, status: "created")

    payment.validate_payment!
    assert_equal "validated", payment.reload.status

    payment.apply!
    assert_equal "applied", payment.reload.status
  end

  test "does not allow applying a payment that has not been validated" do
    loan = Loan.create!(total: 1_000, status: "loan")
    payment = Payment.create!(folio_id: 123, loan: loan, amount: 10, status: "created")

    assert_raises(StateMachines::InvalidTransition) { payment.apply! }
    assert_equal "created", payment.reload.status
  end
end