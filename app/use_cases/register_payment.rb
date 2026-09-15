class RegisterPayment
	def call(folio_id:, loan_id:, amount:)
		amount = BigDecimal(amount.to_s)
		raise InvalidAmountError, "Amount not valid" unless amount.finite? && amount.positive?

		Loan.find(loan_id)
		existing_payment = Payment.find_by(folio_id: folio_id, loan_id: loan_id)
		return resolve_existing(existing_payment, amount) if existing_payment

		Payment.transaction do
			payment = Payment.create!(folio_id: folio_id, loan_id: loan_id, amount: amount, status: "created")
			event = PaymentCreated.new(payment)
			OutboxEvent.create!(event.to_h)
			[payment, true]
		end
	rescue ActiveRecord::RecordNotUnique
		existing_payment = Payment.find_by!(folio_id: folio_id, loan_id: loan_id)
		resolve_existing(existing_payment, amount)
	end

	private

	def resolve_existing(payment, amount)
		return [payment, false] if payment.amount == amount

		raise PaymentConflictError, "Payment already exists with a different amount"
	end
end
