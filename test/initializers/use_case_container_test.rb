require "test_helper"

class UseCaseContainerTest < ActiveSupport::TestCase
  test "memoizes register_payment across resolutions" do
    assert_same UseCaseContainer[:register_payment], UseCaseContainer[:register_payment]
  end

  test "memoizes apply_payment across resolutions" do
    assert_same UseCaseContainer[:apply_payment], UseCaseContainer[:apply_payment]
  end

  test "memoizes kafka_event_publisher across resolutions" do
    assert_same UseCaseContainer[:kafka_event_publisher], UseCaseContainer[:kafka_event_publisher]
  end

  test "memoizes outbox_publisher across resolutions" do
    assert_same UseCaseContainer[:outbox_publisher], UseCaseContainer[:outbox_publisher]
  end

  test "register_payment resolves to a RegisterPayment instance" do
    assert_instance_of RegisterPayment, UseCaseContainer[:register_payment]
  end

  test "apply_payment resolves to an ApplyPayment instance" do
    assert_instance_of ApplyPayment, UseCaseContainer[:apply_payment]
  end
end
