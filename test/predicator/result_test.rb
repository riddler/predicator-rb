# frozen_string_literal: true

require "test_helper"

# A result is a value: ok?, value and error.
class ResultTest < Minitest::Test
  # The package builds results through a private module; the tests reach
  # it by name.
  RESULTS = Predicator.const_get(:Results)

  # sabotage: make Result#ok? answer !value.nil?; a successful null result
  # then reads as failed and the assert_predicate fails.
  def test_a_successful_result_may_answer_null
    result = RESULTS.ok(nil)

    assert_predicate result, :ok?
    assert_nil result.value
    assert_nil result.error
  end

  # sabotage: build Results.failure with error: nil; the refute_predicate
  # on ok? fails.
  def test_a_failed_result_carries_its_error_and_no_value
    error = Predicator::EvaluationError.new(reason: "empty_stack", message: "nothing on the stack")
    result = RESULTS.failure(error)

    refute_predicate result, :ok?
    assert_nil result.value
    assert_same error, result.error
  end

  # sabotage: drop the both-set test from Result#initialize; the
  # assert_raises fails.
  def test_a_result_is_never_both_and_a_failure_is_never_without_an_error
    error = Predicator::EvaluationError.new(reason: "r", message: "m")

    assert_raises(ArgumentError) { Predicator::Result.new(value: 1, error:) }
    assert_raises(ArgumentError) { RESULTS.failure(nil) }
    assert_equal RESULTS.ok(1), Predicator::Result.new(value: 1, error: nil)
  end
end
