class OutboxPublisher
  def initialize(event_publisher: KafkaEventPublisher.new)
    @event_publisher = event_publisher
  end

  def publish_pending(limit: 100)
    OutboxEvent.where(published_at: nil).order(:created_at).limit(limit).find_each do |event|
      publish_event(event)
    end
  end

  private

  def publish_event(event)
    event.with_lock do
      next if event.published_at

      event.update!(attempts: event.attempts + 1)

      begin
        @event_publisher.publish(event)
        event.update!(published_at: Time.current, last_error: nil)
      rescue StandardError => error
        event.update!(last_error: error.message)
      end
    end
  end
end