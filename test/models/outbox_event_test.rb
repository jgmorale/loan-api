require "test_helper"

class OutboxEventTest < ActiveSupport::TestCase
  test "requires a unique event id and event metadata" do
    event_id = SecureRandom.uuid
    attributes = {
      event_id: event_id,
      event_name: "payment.created",
      aggregate_type: "Payment",
      aggregate_id: 1,
      body: { "payment_id" => 1 },
      occurred_at: Time.current
    }

    OutboxEvent.create!(attributes)
    duplicate = OutboxEvent.new(attributes)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:event_id], "has already been taken"
  end
end