module Transitionable
  extend ActiveSupport::Concern

  included do
    state_machine :status, initial: :created, use_transactions: false do
      event :validate_payment do
        transition created: :validated
      end

      event :apply do
        transition validated: :applied
      end
    end

    alias_method :transitionable_validate_payment!, :validate_payment!
    alias_method :transitionable_apply!, :apply!

    def validate_payment!(*args)
      transitionable_validate_payment!(*args, false).tap do |result|
        persist_transition! if result
      end
    end

    def apply!(*args)
      transitionable_apply!(*args, false).tap do |result|
        persist_transition! if result
      end
    end
  end

  private

  def persist_transition!
    save!(validate: false)
  end
end