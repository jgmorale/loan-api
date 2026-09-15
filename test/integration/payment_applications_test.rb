require "test_helper"

class PaymentApplicationsTest < ActionDispatch::IntegrationTest
  setup do
    @loan = Loan.create!(total: 1_000, status: "loan")
  end

  test "returns 404 when the payment application does not exist" do
    get loan_payment_application_path(@loan, 456)

    assert_response :not_found
  end
end