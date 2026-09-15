class ApplicationController < ActionController::API
	rescue_from ActionController::BadRequest, with: :render_bad_request
	rescue_from InvalidAmountError, with: :render_invalid_amount
	rescue_from PaymentConflictError, with: :render_conflict

	private

	def render_bad_request(error)
		render json: { result: "bad_request", message: error.message }, status: :bad_request
	end

	def render_invalid_amount(error)
		render json: { result: "bad_request", message: error.message }, status: :bad_request
	end

	def render_conflict(error)
		render json: { result: "conflict", message: error.message }, status: :conflict
	end
end
