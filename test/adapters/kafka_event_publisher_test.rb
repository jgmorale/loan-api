require "test_helper"

class KafkaEventPublisherTest < ActiveSupport::TestCase
  test "publishes the event with its id as the message key" do
    producer = Object.new
    producer.define_singleton_method(:deliver_messages) { true }
    producer.define_singleton_method(:produce) do |payload, topic:, key:, headers:|
      @message = { payload: payload, topic: topic, key: key, headers: headers }
    end

    event = OutboxEvent.new(
      event_id: "123e4567-e89b-12d3-a456-426614174000",
      event_name: "payment.created",
      aggregate_type: "Payment",
      aggregate_id: 9,
      body: { "payment_id" => 9 },
      occurred_at: Time.utc(2026, 9, 14, 12)
    )

    KafkaEventPublisher.new(producer: producer, topic: "payments").publish(event)

    assert_equal "123e4567-e89b-12d3-a456-426614174000", producer.instance_variable_get(:@message).fetch(:key)
    assert_equal "payments", producer.instance_variable_get(:@message).fetch(:topic)
    assert_equal({ "payment_id" => 9 }.to_json, producer.instance_variable_get(:@message).fetch(:payload))
  end
end