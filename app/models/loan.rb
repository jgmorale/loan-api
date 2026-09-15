class Loan < ApplicationRecord
  has_many :payment_applications, dependent: :restrict_with_exception

  state_machine :status, initial: :loan do
    state :loan
    state :created
    state :approved
    state :disbursed
    state :paid

    event :paid do
      transition [:loan, :disbursed] => :paid
    end
  end
end
