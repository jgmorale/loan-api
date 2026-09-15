Rails.application.config.x.kafka_brokers = ENV.fetch("KAFKA_BROKERS", "localhost:9092").split(",")
Rails.application.config.x.kafka_payments_topic = ENV.fetch("KAFKA_PAYMENTS_TOPIC", "payments")