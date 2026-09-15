require "test_helper"

class OutboxPublisherTest < ActiveSupport::TestCase
  setup do
    @event = OutboxEvent.create!(
      event_id: SecureRandom.uuid,
      event_name: "payment.created",
      aggregate_type: "Payment",
      aggregate_id: 1,
      body: { "payment_id" => 1 },
      occurred_at: Time.current
    )
  end

  test "marks an event published only after the transport succeeds" do
    publisher = Class.new do
      attr_reader :events

      def initialize
        @events = []
      end

      def publish(event)
        @events << event
      end
    end.new

    OutboxPublisher.new(event_publisher: publisher).publish_pending

    assert_not_nil @event.reload.published_at
    assert_equal 1, @event.attempts
    assert_equal [@event.id], publisher.events.map(&:id)
  end

  test "records a failed attempt without marking the event published" do
    publisher = Object.new
    def publisher.publish(_event)
      raise "broker unavailable"
    end

    OutboxPublisher.new(event_publisher: publisher).publish_pending

    @event.reload
    assert_nil @event.published_at
    assert_equal 1, @event.attempts
    assert_equal "broker unavailable", @event.last_error
  end
end