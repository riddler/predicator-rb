# frozen_string_literal: true

require "test_helper"
require_relative "evaluator_helper"

# How `call` reaches a function, the host's or the library's, and how it is
# refused.
class EvaluatorCallsTest < Minitest::Test
  include EvaluatorHelper

  def call(name, *args) = [*args.map { |arg| ["lit", arg] }, ["call", name, args.size]]

  def answer(instructions, **)
    result = run_list(instructions, {}, **)
    assert_predicate result, :ok?, -> { "failed with #{result.error.inspect}" }
    result.value
  end

  # The reason of the EvaluationError a call is refused with, which is its
  # message too but for insufficient_arguments.
  def refusal(instructions, **)
    result = run_list(instructions, {}, **)
    refute_predicate result, :ok?, -> { "answered #{result.value.inspect}" }
    error = result.error
    assert_equal "EvaluationError", error.type
    assert_equal error.message, error.reason unless error.reason == "insufficient_arguments"
    error.reason
  end

  # sabotage: pass the popped arguments reversed in Calls#call_function
  # (`dispatch(name, args.reverse)`); the first assert_equal fails.
  def test_a_host_function_takes_its_arguments_first_argument_first
    joined = { "join" => ->(a, b, c) { "#{a}#{b}#{c}" } }
    assert_equal "xyz", answer(call("join", "x", "y", "z"), functions: joined)
    pair = { "pair" => ->(*a) { a } }
    assert_equal ["x", 1], answer([%w[lit x], ["lit", 1], ["call", "pair", 2]], functions: pair)
  end

  # sabotage: look the library up before the host's functions in
  # Calls#resolve; len answers 1 and the assert_equal fails.
  def test_a_host_function_shadows_the_library_for_its_evaluation_only
    assert_equal "shadowed", answer(call("len", "x"), functions: { "len" => ->(_) { "shadowed" } })
    assert_equal 1, answer(call("len", "x"))
  end

  # sabotage: guard the count with `@stack.size < arg_count && resolve(name)`
  # in Calls#call_function; an unknown name with an empty stack answers
  # Unknown function and the first assert_equal fails.
  def test_too_few_values_on_the_stack_is_refused_before_the_name_is_read
    assert_equal "insufficient_arguments", refusal([["call", "nope", 1]])
    assert_equal "Function len() expects 2 arguments, but only 1 values on stack",
                 run_list([%w[lit x], ["call", "len", 2]]).error.message
  end

  # sabotage: answer `"Unknown function"` without the name in
  # Calls#dispatch; the first assert_equal fails.
  def test_an_unknown_name_is_refused_by_its_name
    assert_equal "Unknown function: nope", refusal(call("nope", 1))
    assert_equal "Unknown function: lenx", refusal(call("lenx", "x"), functions: { "x" => -> {} })
  end

  HOST = {
    "one" => ->(a) { a }, "opt" => ->(a, b = 0) { a + b }, "rest" => ->(a, *rest) { a + rest.size },
    "block" => proc { |a, b| [a, b] }, "method" => 1.method(:+), "object" => Object.new.tap { |o| def o.call = 7 }
  }.freeze

  # sabotage: answer `(required..)` for every callable in Calls.counts;
  # `one` is called with two arguments, raises, and the first assert_equal
  # reads the raised sentence.
  def test_a_host_function_takes_the_counts_its_parameters_take
    host = HOST
    assert_equal "Function one() expects 1 arguments, got 2", refusal(call("one", 1, 2), functions: host)
    assert_equal "Function opt() expects 1 or 2 arguments, got 3", refusal(call("opt", 1, 2, 3), functions: host)
    assert_equal "Function rest() expects at least 1 arguments, got 0", refusal(call("rest"), functions: host)
    assert_equal "Function block() expects 2 arguments, got 1", refusal(call("block", 1), functions: host)
    assert_equal "Function object() expects 0 arguments, got 1", refusal(call("object", 1), functions: host)
  end

  # sabotage: answer `required..required` for every callable in
  # Calls.counts; `opt` with two arguments is refused and answer's
  # assert_predicate fails.
  def test_a_host_function_answers_each_count_its_parameters_take
    answers = [["opt", 1, 2], ["rest", 1, 1, 1], ["rest", 1, 1, 1, 1], ["block", 1, 2], ["method", 1], ["object"]]
              .map { |name, *args| answer(call(name, *args), functions: HOST) }
    assert_equal [3, 3, 4, [1, 2], 2, 7], answers
  end

  # sabotage: write `e.message` for `e.inspect` in Calls#dispatch; the
  # reason drops the class and the assert_equal fails.
  def test_a_function_that_raises_is_refused_naming_the_exception
    host = { "boom" => ->(_) { raise ArgumentError, "no" } }
    assert_equal "Function boom() raised: #<ArgumentError: no>", refusal(call("boom", 1), functions: host)
  end

  # sabotage: answer `push(at, answer)` in Calls#call_function; a refused
  # call pushes its error, the run answers true and refusal's
  # refute_predicate fails.
  def test_a_function_may_answer_any_value_and_a_refusal_stops_the_run
    assert_equal "len() expects a string argument", refusal([*call("len", 1), ["lit", true]])
    assert_nil answer(call("nil", 1), functions: { "nil" => ->(_) {} })
    assert_same Predicator::UNDEFINED, answer(call("absent"), functions: { "absent" => -> { Predicator::UNDEFINED } })
  end

  # sabotage: drop the String check on a name in
  # Evaluator.check_functions; a Symbol name passes and the second
  # assert_raises fails.
  def test_the_functions_option_is_checked
    assert_raises(ArgumentError) { run_list([], {}, functions: []) }
    assert_raises(ArgumentError) { run_list([], {}, functions: { x: -> {} }) }
    assert_raises(ArgumentError) { run_list([], {}, functions: { "x" => 1 }) }
  end

  # sabotage: give the call row the operands `%i[value count]`; the Symbol
  # name runs, answers Unknown function, and assert_fails's assert_equal
  # fails on the second instruction.
  def test_a_malformed_call_is_an_unknown_instruction
    [["call", "len", -1], ["call", :len, 1], %w[call len], ["call", "len", 1.0]].each do |instruction|
      assert_fails "EvaluationError", "unknown_instruction", [%w[lit x], instruction]
    end
  end
end
