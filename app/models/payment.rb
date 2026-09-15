class Payment < ApplicationRecord
  STATUSES = %w[created validated applied].freeze

  belongs_to :loan

  validates :folio_id, :amount, :status, presence: true
  validates :folio_id, uniqueness: { scope: :loan_id }
  validates :amount, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }
end