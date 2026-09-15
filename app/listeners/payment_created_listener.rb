class PaymentCreatedListener
  def call(event)
    payment = Payment.find(event_aggregate_id(event))
    return payment if payment.status == "applied"

    Payment.transaction do
      loan = payment.loan
      validate_payment!(payment, loan)
      payment.update!(status: "validated") if payment.status == "created"

      apply_payment.call(
        loan_id: payment.loan_id,
        payment_id: payment.id,
        amount: payment.amount
      )

      payment.update!(status: "applied")
    end

    payment.reload
  end

  private

  def apply_payment
    UseCaseContainer[:apply_payment]
  end

  def event_aggregate_id(event)
    return event.aggregate_id if event.respond_to?(:aggregate_id)

    event.fetch("aggregate_id")
  end

  def validate_payment!(payment, loan)
    raise InvalidAmountError, "Amount not valid" if payment.amount <= 0
    raise InvalidAmountError, "Payment amount should be less than total amount" if loan.total < payment.amount
  end
end