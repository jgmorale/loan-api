module PaymentTransitionable
  extend ActiveSupport::Concern

  included do
    state_machine :status, initial: :created, use_transactions: false do
      event :applied do
        transition created: :applied
      end

      event :rejected do
        transition created: :rejected
      end
    end
  end
end
