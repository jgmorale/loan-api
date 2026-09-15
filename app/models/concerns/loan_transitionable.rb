module LoanTransitionable
  extend ActiveSupport::Concern

  included do
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
end