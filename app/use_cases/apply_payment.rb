class ApplyPayment
  def call(payment_id:, loan_id:, amount:)
    raise InvalidAmountError, "Amount not valid" if amount <= 0

    Loan.transaction do
      loan = Loan.lock.find(loan_id)

      payment_application = PaymentApplication.find_by(
                                                       loan_id: loan_id,
                                                       payment_id: payment_id
                                                      )

      next payment_application if payment_application.present?

      raise InvalidAmountError, "Payment amount should be less than total amount" if loan.total < amount

      loan.update!(total: loan.total - amount)

      if loan.total.zero?
        loan.paid!(run_action: false)
        loan.save!
      end

      PaymentApplication.create!(
                                 loan_id: loan_id,
                                 payment_id: payment_id,
                                 amount: amount,
                                 remaining_balance: loan.total
                                )
    end
  end
end
