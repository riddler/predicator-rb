# frozen_string_literal: true

# The assertions the evaluator's tests share. The evaluator is private to
# the package, so they reach it by name.
module EvaluatorHelper
  EVALUATOR = Predicator.const_get(:Evaluator)

  def run_list(instructions, context = {}, **) = EVALUATOR.evaluate(instructions, context, **)

  def assert_answers(expected, instructions, context = {}, **)
    result = run_list(instructions, context, **)

    assert_predicate result, :ok?, -> { "failed with #{result.error.inspect}" }
    if expected.nil?
      assert_nil result.value
    else
      assert_same expected, result.value
    end
  end

  def assert_fails(type, reason, instructions, context = {}, **)
    result = run_list(instructions, context, **)

    refute_predicate result, :ok?, -> { "answered #{result.value.inspect}" }
    assert_equal [type, reason], [result.error.type, result.error.reason]
    result.error
  end
end
