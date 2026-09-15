require "test_helper"

class InternalPaymentApplicationsTest < ActionDispatch::IntegrationTest
  setup do
    @loan = Loan.create!(total: 1_000, status: "loan")
  end

  test "returns 404 when the payment application does not exist" do
        get "/v1/internal/loans/#{@loan.id}/payment-applications/999",
          as: :json

    assert_response :not_found
  end
end