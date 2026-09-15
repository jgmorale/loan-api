class PaymentCreatedListener
  def call(event)
    payment = Payment.find(event_aggregate_id(event))
    return payment if payment.status == "applied"

    Payment.transaction do
      apply_payment.call(
        loan_id: payment.loan_id,
        payment_id: payment.id,
        amount: payment.amount
      )

      payment.applied!(run_action: false)
      payment.save!
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
end