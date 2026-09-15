class PaymentApplication < ApplicationRecord
  belongs_to :loan

  validates :payment_id, uniqueness: { scope: :loan_id }
end