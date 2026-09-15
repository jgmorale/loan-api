class Loan < ApplicationRecord
  include LoanTransitionable

  has_many :payment_applications, dependent: :restrict_with_exception
end
