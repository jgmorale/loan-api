class PaymentAppliedListener
  def call(event)
    payment = Payment.find(event_aggregate_id(event))
    return if payment.status != 'applied'

    notify_payment.notify(payment)
  end

  private

  def notify_payment
    UseCaseContainer[:notify_payment]
  end

  def event_aggregate_id(event)
    return event.aggregate_id if event.respond_to?(:aggregate_id)

    event.fetch("aggregate_id")
  end
end
