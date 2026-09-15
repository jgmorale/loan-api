require "test_helper"

class ExternalPaymentsTest < ActionDispatch::IntegrationTest
  setup do
    @loan = Loan.create!(total: 1_000, status: "loan")
  end

  test "registers a payment without changing the loan balance" do
    post "/v1/external/payments",
         params: { folio_id: 123, loan_id: @loan.id, amount: "700.00" },
         as: :json

    assert_response :created
    assert_equal "created", response.parsed_body.fetch("payment").fetch("status")
    assert_equal 1_000, @loan.reload.total
  end

  test "returns 200 for an identical repeated registration" do
    payload = { folio_id: 123, loan_id: @loan.id, amount: "700.00" }
    post "/v1/external/payments", params: payload, as: :json
    post "/v1/external/payments", params: payload, as: :json

    assert_response :ok
    assert_equal 1, Payment.count
    assert_equal 1, OutboxEvent.count
  end

  test "returns 409 when a repeated registration changes the amount" do
    post "/v1/external/payments",
         params: { folio_id: 123, loan_id: @loan.id, amount: "700.00" },
         as: :json

    post "/v1/external/payments",
         params: { folio_id: 123, loan_id: @loan.id, amount: "600.00" },
         as: :json

    assert_response :conflict
  end

  test "returns 400 for a malformed amount" do
    post "/v1/external/payments",
         params: { folio_id: 123, loan_id: @loan.id, amount: "not-a-number" },
         as: :json

    assert_response :bad_request
  end
end