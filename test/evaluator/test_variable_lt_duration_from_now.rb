# AUTOGENERATED FILE - DO NOT EDIT
require "helper"

class VariableLtDurationFromNowTest < ::Minitest::Test
  attr_reader :instructions

  def setup
    @instructions = [["load", "plan_end_date"], ["to_date"], ["lit", 259200], ["date_from_now"], ["compare", "LT"]]
  end

  def test_with_no_context
    context = nil
    expected_result = false

    e = ::Predicator::Evaluator.new instructions, context
    assert_equal expected_result, e.result
    assert_empty e.stack
  end

  def test_with_blank_date
    context = {"plan_end_date"=>""}
    expected_result = false

    e = ::Predicator::Evaluator.new instructions, context
    assert_equal expected_result, e.result
    assert_empty e.stack
  end

  def test_with_future_date
    context = {"plan_end_date"=>"2299-01-01"}
    expected_result = false

    e = ::Predicator::Evaluator.new instructions, context
    assert_equal expected_result, e.result
    assert_empty e.stack
  end

  def test_with_past_date
    context = {"plan_end_date"=>"1999-01-01"}
    expected_result = true

    e = ::Predicator::Evaluator.new instructions, context
    assert_equal expected_result, e.result
    assert_empty e.stack
  end

end
