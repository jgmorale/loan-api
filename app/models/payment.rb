class Payment < ApplicationRecord
  include PaymentTransitionable

  belongs_to :loan

  validates :folio_id, :amount, presence: true
  validates :folio_id, uniqueness: { scope: :loan_id }
  validates :amount, numericality: { greater_than: 0 }
end
