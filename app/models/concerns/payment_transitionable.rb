module PaymentTransitionable
  extend ActiveSupport::Concern

  included do
    state_machine :status, initial: :created, use_transactions: false do
      event :validated do
        transition created: :validated
      end

      event :applied do
        transition validated: :applied
      end
    end
  end
end