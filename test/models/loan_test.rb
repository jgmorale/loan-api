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