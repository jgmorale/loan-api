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