class LoansController < ApplicationController
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  def show
    loan = Loan.find(params[:id])

    render json: {
      id: loan.id,
      total: loan.total,
      status: loan.status
    }
  end

  private

  def render_not_found(error)
    render json: { result: "not_found", message: error.message }, status: :not_found
  end
end