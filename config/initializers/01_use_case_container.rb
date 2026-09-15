require "dry-container"
require "dry-auto_inject"

UseCaseContainer = Dry::Container.new

UseCaseContainer.register(:kafka_event_publisher, memoize: true) { KafkaEventPublisher.new }

UseCaseContainer.register(:outbox_publisher, memoize: true) do
  OutboxPublisher.new(event_publisher: UseCaseContainer[:kafka_event_publisher])
end

UseCaseContainer.register(:register_payment, memoize: true) { RegisterPayment.new }

UseCaseContainer.register(:apply_payment, memoize: true) { ApplyPayment.new }
