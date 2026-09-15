class PaymentApplicationsController < ApplicationController
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  def show
    payment_application = PaymentApplication.find_by!(
      loan_id: loan_id,
      payment_id: payment_id
    )

    render json: { payment_application: payment_application_json(payment_application) }
  end

  private

  def loan_id
    Integer(params[:loan_id], 10)
  rescue ArgumentError, TypeError
    raise ActionController::BadRequest, "loan_id must be an integer"
  end

  def payment_id
    Integer(params[:payment_id], 10)
  rescue ArgumentError, TypeError
    raise ActionController::BadRequest, "payment_id must be an integer"
  end

  def payment_application_json(payment_application)
    {
      loan_id: payment_application.loan_id,
      payment_id: payment_application.payment_id,
      amount: payment_application.amount,
      remaining_balance: payment_application.remaining_balance
    }.compact
  end

  def render_not_found(error)
    render json: { result: "not_found", message: error.message }, status: :not_found
  end
end