require "test_helper"

class V1::External::PaymentsControllerTest < ActiveSupport::TestCase
  test "#register_payment resolves the memoized use case from the container" do
    controller = V1::External::PaymentsController.new

    assert_same UseCaseContainer[:register_payment], controller.send(:register_payment)
  end
end
