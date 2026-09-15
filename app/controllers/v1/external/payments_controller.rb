module V1
  module External
    class PaymentsController < ApplicationController
      def create
        payment, created = RegisterPayment.new.call(
          folio_id: integer_param(:folio_id),
          loan_id: integer_param(:loan_id),
          amount: amount_param
        )

        render json: { payment: payment_json(payment) }, status: created ? :created : :ok
      end

      private

      def integer_param(name)
        value = Integer(params.require(name).to_s, 10)
        raise ArgumentError unless value.positive?

        value
      rescue ArgumentError, TypeError
        raise ActionController::BadRequest, "#{name} must be an integer"
      end

      def amount_param
        value = params.require(:amount)
        amount = BigDecimal(value.to_s)
        raise ArgumentError unless amount.finite?

        amount
      rescue ArgumentError
        raise ActionController::BadRequest, "amount must be a number"
      end

      def payment_json(payment)
        {
          id: payment.id,
          folio_id: payment.folio_id,
          loan_id: payment.loan_id,
          amount: payment.amount,
          status: payment.status,
          created_at: payment.created_at
        }
      end
    end
  end
end