class PaymentCreated
  attr_reader :event_id, :event_name, :aggregate_type, :aggregate_id, :occurred_at, :body

  def initialize(payment)
    @event_id = SecureRandom.uuid
    @event_name = "payment.created"
    @aggregate_type = "Payment"
    @aggregate_id = payment.id
    @occurred_at = Time.current
    @body = {
      "payment_id" => payment.id,
      "folio_id" => payment.folio_id,
      "loan_id" => payment.loan_id,
      "amount" => payment.amount.to_s,
      "status" => payment.status,
      "created_at" => payment.created_at.iso8601
    }
  end

  def to_h
    {
      event_id: event_id,
      event_name: event_name,
      aggregate_type: aggregate_type,
      aggregate_id: aggregate_id,
      body: body,
      occurred_at: occurred_at
    }
  end
end