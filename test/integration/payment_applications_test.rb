require "test_helper"

class PaymentApplicationsTest < ActionDispatch::IntegrationTest
  setup do
    @loan = Loan.create!(total: 1_000, status: "loan")
  end

  test "returns 404 when the payment application does not exist" do
    get loan_payment_application_path(@loan, 456)

    assert_response :not_found
  end

  test "does not expose an update endpoint" do
    assert_raises(ActionController::RoutingError) do
      patch loan_payment_application_path(@loan, 456), params: { amount: 100 }
    end

    assert_equal 0, PaymentApplication.count
  end
end