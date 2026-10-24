# frozen_string_literal: true

require "test_helper"
require_relative "evaluator_helper"

# The five arithmetic opcodes: Integer and Float kept apart, the zero
# checks before the type checks, the string and list rules of add and
# subtract, and the refusals. The date rules are EvaluatorDateArithmeticTest.
class EvaluatorArithmeticTest < Minitest::Test
  include EvaluatorHelper

  def answer(left, right, opcode)
    result = run_list([["lit", left], ["lit", right], [opcode]])
    assert_predicate result, :ok?, -> { "failed with #{result.error.inspect}" }
    result.value
  end

  # sabotage: change `left * right` to `(left * right).to_i` in
  # Machine#multiply; the assert_instance_of Float on 2 * 1.5 fails.
  def test_two_integers_answer_an_integer_and_a_float_answers_a_float
    assert_answers 5, [["lit", 2], ["lit", 3], ["add"]]
    assert_answers 7, [["lit", 10], ["lit", 3], ["subtract"]]
    assert_answers 42, [["lit", 6], ["lit", 7], ["multiply"]]
    assert_instance_of Float, answer(2, 1.5, "multiply")
    assert_in_delta 3.0, answer(2, 1.5, "multiply")
    assert_instance_of Float, answer(1.5, 1, "add")
    assert_instance_of Float, answer(2.0, 2, "subtract")
  end

  # sabotage: replace truncated_quotient's body with `left / right` (Ruby's
  # floor division); -7 / 2 answers -4 and the assert_answers(-3, ...)'s
  # assert_same fails.
  def test_two_integers_divide_by_truncating_toward_zero
    assert_answers 3, [["lit", 7], ["lit", 2], ["divide"]]
    assert_answers(-3, [["lit", -7], ["lit", 2], ["divide"]])
    assert_answers(-3, [["lit", 7], ["lit", -2], ["divide"]])
    assert_answers 3, [["lit", -7], ["lit", -2], ["divide"]]
    assert_in_delta 3.5, answer(7.0, 2, "divide")
    assert_in_delta 3.5, answer(7, 2.0, "divide")
  end

  # sabotage: replace `left.remainder(right)` with `left % right` in
  # Machine#modulo; -7 % 2 answers 1 and the assert_answers(-1, ...)'s
  # assert_same fails.
  def test_modulo_takes_the_sign_of_the_dividend
    assert_answers 1, [["lit", 7], ["lit", 2], ["modulo"]]
    assert_answers(-1, [["lit", -7], ["lit", 2], ["modulo"]])
    assert_answers 1, [["lit", 7], ["lit", -2], ["modulo"]]
  end

  # sabotage: drop the `zero:` argument from Machine#divide's call to
  # arithmetic; true / 0 answers a type mismatch and the first
  # assert_fails's assert_equal fails.
  def test_a_zero_divisor_is_refused_before_the_types_are
    assert_fails "EvaluationError", "division_by_zero", [["lit", true], ["lit", 0], ["divide"]]
    assert_fails "EvaluationError", "division_by_zero", [["lit", 1], ["lit", 0.0], ["divide"]]
    assert_fails "EvaluationError", "division_by_zero", [["lit", 1.5], ["lit", -0.0], ["divide"]]
    assert_fails "EvaluationError", "modulo_by_zero", [%w[lit x], ["lit", 0], ["modulo"]]
  end

  # sabotage: widen Machine#modulo's zero check to `number?(right) &&
  # right.zero?`; 5 % 0.0 answers modulo_by_zero and the first assert_fails's
  # assert_equal fails.
  def test_modulo_takes_integers_only_and_a_float_zero_is_a_type_mismatch
    assert_fails "TypeMismatchError", "modulo", [["lit", 5], ["lit", 0.0], ["modulo"]]
    assert_fails "TypeMismatchError", "modulo", [["lit", 5.0], ["lit", 2], ["modulo"]]
    assert_fails "TypeMismatchError", "modulo", [["lit", 5], ["lit", 2.0], ["modulo"]]
  end

  # sabotage: drop the String-String clause from Arithmetic#sum's first
  # line; "a" + "b" is refused and the answer helper's assert_predicate
  # fails.
  def test_add_joins_strings_and_lists_and_writes_a_number_as_text
    assert_equal "ab", answer("a", "b", "add")
    assert_equal "x: 5", answer("x: ", 5, "add")
    assert_equal "5 x", answer(5, " x", "add")
    assert_equal "x1.5", answer("x", 1.5, "add")
    assert_equal "x1.0e3", answer("x", 1000.0, "add")
    assert_equal [1, 2, 3], answer([1], [2, 3], "add")
  end

  # sabotage: make Arithmetic#difference answer `left + right` for strings
  # by adding `return left + right if both?(left, right, String)`; "ab" -
  # "a" answers "aba" and the first assert_fails's refute_predicate fails.
  def test_subtract_never_joins
    assert_fails "TypeMismatchError", "subtract", [%w[lit ab], %w[lit a], ["subtract"]]
    assert_fails "TypeMismatchError", "subtract", [["lit", [1]], ["lit", [1]], ["subtract"]]
  end

  # sabotage: change Machine#multiply's guard to `number?(right)`; "x" * 5
  # answers "xxxxx" and the second assert_fails's refute_predicate fails.
  def test_every_other_pair_is_a_type_mismatch_naming_the_opcode
    assert_fails "TypeMismatchError", "multiply", [["lit", 5], ["lit", true], ["multiply"]]
    assert_fails "TypeMismatchError", "multiply", [%w[lit x], ["lit", 5], ["multiply"]]
    assert_fails "TypeMismatchError", "add", [["lit", nil], ["lit", 1], ["add"]]
    assert_fails "TypeMismatchError", "add", [["lit", Predicator::UNDEFINED], ["lit", 1], ["add"]]
    assert_fails "TypeMismatchError", "divide", [%w[lit x], ["lit", 2], ["divide"]]
  end

  # sabotage: make Arithmetic#mismatch_pair always report left; 1 + x
  # answers a TypeMismatchError and the first assert_fails's assert_equal
  # fails.
  def test_an_unbound_operand_on_either_side_names_the_variable
    assert_fails "UndefinedVariableError", "unbound_variable", [["lit", 1], %w[load x], ["add"]]
    assert_fails "UndefinedVariableError", "unbound_variable", [%w[load x], ["lit", 1], ["multiply"]]
  end

  # sabotage: drop the finite check from Machine#arithmetic; the overflow
  # answers Infinity and the first assert_fails's refute_predicate fails.
  def test_a_float_answer_that_is_not_finite_is_refused
    assert_fails "EvaluationError", "non_finite_number", [["lit", 1.0e308], ["lit", 10], ["multiply"]]
    assert_fails "EvaluationError", "non_finite_number", [["lit", 1.0e308], ["lit", 1.0e-308], ["divide"]]
    assert_fails "EvaluationError", "non_finite_number", [["lit", 1.0e308], ["lit", 1.0e308], ["add"]]
  end

  # sabotage: replace `left * right` in Machine#multiply with
  # `(left * right) % (2**64)`; the product wraps and the assert_equal fails.
  def test_integers_have_no_bound
    assert_equal 2**70, answer(2**35, 2**35, "multiply")
  end

  # sabotage: change Machine#arithmetic's depth check to `@stack.empty?`;
  # one operand pops nil as left and the assert_fails's assert_equal fails.
  def test_too_few_operands_is_an_evaluation_error
    %w[add subtract multiply divide modulo].each do |opcode|
      assert_fails "EvaluationError", "insufficient_operands", [["lit", 0], [opcode]]
    end
  end
end
