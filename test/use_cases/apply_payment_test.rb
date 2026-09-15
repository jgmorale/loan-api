require "test_helper"

class ApplyPaymentTest < ActiveSupport::TestCase
  setup do
    @loan = Loan.create!(total: 1_000, status: "loan")
    @use_case = ApplyPayment.new
  end

  test "applies a payment and stores the remaining balance" do
    application = @use_case.call(loan_id: @loan.id, payment_id: 456, amount: 700)

    assert_equal @loan.id, application.loan_id
    assert_equal 456, application.payment_id
    assert_equal 700, application.amount
    assert_equal 300, application.remaining_balance
    assert_equal 300, @loan.reload.total
    assert_equal "loan", @loan.status
  end

  test "returns the existing application without applying the payment twice" do
    first = @use_case.call(loan_id: @loan.id, payment_id: 456, amount: 700)
    second = @use_case.call(loan_id: @loan.id, payment_id: 456, amount: 700)

    assert_equal first.id, second.id
    assert_equal 300, @loan.reload.total
    assert_equal 1, PaymentApplication.where(loan_id: @loan.id, payment_id: 456).count
  end

  test "allows only one of two concurrent payments that exceed the loan balance together" do
    ready = Queue.new
    start = Queue.new
    calls = 2.times.map do |index|
      Thread.new do
        ready << true
        start.pop
        [index, @use_case.call(loan_id: @loan.id, payment_id: index + 1, amount: 700)]
      rescue InvalidAmountError => error
        [index, error]
      end
    end

    2.times { ready.pop }
    2.times { start << true }
    results = calls.map(&:value)

    assert_equal 1, results.count { |_, result| result.is_a?(PaymentApplication) }
    assert_equal 1, results.count { |_, result| result.is_a?(InvalidAmountError) }
    assert_equal 1, PaymentApplication.where(loan_id: @loan.id).count
    assert_equal 300, @loan.reload.total
  end

  test "marks the loan as paid when the remaining balance reaches zero" do
    @use_case.call(loan_id: @loan.id, payment_id: 456, amount: 1_000)

    assert_equal "paid", @loan.reload.status
  end

  test "rejects non-positive amounts" do
    error = assert_raises(InvalidAmountError) do
      @use_case.call(loan_id: @loan.id, payment_id: 456, amount: 0)
    end

    assert_equal "Amount not valid", error.message
  end

  test "rejects payments greater than the loan total" do
    error = assert_raises(InvalidAmountError) do
      @use_case.call(loan_id: @loan.id, payment_id: 456, amount: 1_001)
    end

    assert_equal "Payment amount should be less than total amount", error.message
  end
end