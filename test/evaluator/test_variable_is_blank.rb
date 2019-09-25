# AUTOGENERATED FILE - DO NOT EDIT
require "helper"

class VariableIsBlankTest < ::Minitest::Test
  attr_reader :instructions

  def setup
    @instructions = [["load", "foo"], ["blank"]]
  end

  def test_with_no_context
    context = nil
    expected_result = true

    e = ::Predicator::Evaluator.new instructions, context
    assert_equal expected_result, e.result
    assert_empty e.stack
  end

  def test_with_blank_string
    context = {"foo"=>""}
    expected_result = true

    e = ::Predicator::Evaluator.new instructions, context
    assert_equal expected_result, e.result
    assert_empty e.stack
  end

  def test_with_int
    context = {"foo"=>1}
    expected_result = false

    e = ::Predicator::Evaluator.new instructions, context
    assert_equal expected_result, e.result
    assert_empty e.stack
  end

  def test_with_string
    context = {"foo"=>"bar"}
    expected_result = false

    e = ::Predicator::Evaluator.new instructions, context
    assert_equal expected_result, e.result
    assert_empty e.stack
  end

end