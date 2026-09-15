require "json"

class KafkaEventPublisher
  def initialize(producer: default_producer, topic: default_topic)
    @producer = producer
    @topic = topic
  end

  def publish(event)
    @producer.produce(
      JSON.generate(event.body),
      topic: @topic,
      key: event.event_id,
      headers: {
        "event_name" => event.event_name,
        "aggregate_type" => event.aggregate_type,
        "occurred_at" => event.occurred_at.iso8601
      }
    )
    @producer.deliver_messages
  end

  private

  def default_producer
    Kafka.new(Rails.application.config.x.kafka_brokers, client_id: "loan-api").producer
  end

  def default_topic
    Rails.application.config.x.kafka_payments_topic
  end
end