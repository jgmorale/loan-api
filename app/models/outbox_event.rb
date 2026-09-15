class OutboxEvent < ApplicationRecord
  validates :event_id, :event_name, :aggregate_type, :aggregate_id, :body, :occurred_at, presence: true
  validates :event_id, uniqueness: true
  validates :attempts, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end