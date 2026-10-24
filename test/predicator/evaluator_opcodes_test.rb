# frozen_string_literal: true

require "test_helper"
require_relative "evaluator_helper"

# The evaluator's unary opcodes and its two short-circuit jumps: the
# operand each takes, the falsy set at a jump, and too few operands.
class EvaluatorOpcodesTest < Minitest::Test
  include EvaluatorHelper

  # sabotage: make the boolean check in Machine#negate `unless true`;
  # ["lit", 5], ["not"] answers false and that assert_fails's
  # refute_predicate fails.
  def test_not_and_unary_bang_take_a_boolean
    assert_answers false, [["lit", true], ["not"]]
    assert_answers true, [["lit", false], ["unary_bang"]]
    assert_fails "TypeMismatchError", "logical_not", [["lit", 5], ["not"]]
    assert_fails "TypeMismatchError", "unary_bang", [["lit", nil], ["unary_bang"]]
  end

  # sabotage: drop the Float half of the check in Machine#unary_minus; 1.5
  # is refused and the assert_equal on -1.5 fails.
  def test_unary_minus_takes_a_number
    assert_answers(-5, [["lit", 5], ["unary_minus"]])
    assert_equal(-1.5, run_list([["lit", 1.5], ["unary_minus"]]).value)
    assert_fails "TypeMismatchError", "unary_minus", [["lit", true], ["unary_minus"]]
  end

  # sabotage: drop the empty-stack check from Machine#negate; popping nil
  # answers a TypeMismatchError and the first assert_fails's assert_equal
  # fails.
  def test_too_few_operands_is_an_evaluation_error_before_any_type_check
    assert_fails "EvaluationError", "insufficient_operands", [["not"]]
    assert_fails "EvaluationError", "insufficient_operands", [["unary_minus"]]
    assert_fails "EvaluationError", "insufficient_operands", [["lit", 1], %w[compare LT]]
    assert_fails "EvaluationError", "insufficient_operands", [["jump_if_true_or_pop", 1]]
  end

  # sabotage: drop `value.nil?` from Machine#truth; a null top is refused
  # and assert_answers's assert_predicate on null fails.
  def test_the_falsy_set_at_a_jump_is_false_null_and_undefined
    [false, nil, Predicator::UNDEFINED].each do |falsy|
      assert_answers falsy, [["lit", falsy], ["jump_if_falsy_or_pop", 2], ["lit", 1]]
      assert_answers 1, [["lit", falsy], ["jump_if_true_or_pop", 2], ["lit", 1]]
    end
  end

  # sabotage: pass true as jump_on in Machine#jump_if_falsy_or_pop; a true
  # left answers true and the first assert_answers's assert_same fails.
  def test_true_falls_through_one_jump_and_takes_the_other
    assert_answers 1, [["lit", true], ["jump_if_falsy_or_pop", 2], ["lit", 1]]
    assert_answers true, [["lit", true], ["jump_if_true_or_pop", 2], ["lit", 1]]
  end

  # sabotage: drop the truth.nil? refusal from Machine#conditional_jump;
  # ["lit", 0] pops and falls through, and the first assert_fails's
  # refute_predicate fails.
  def test_a_jump_refuses_anything_but_false_null_undefined_and_true
    assert_fails "TypeMismatchError", "jump_if_falsy_or_pop", [["lit", 0], ["jump_if_falsy_or_pop", 2], ["lit", 1]]
    assert_fails "TypeMismatchError", "jump_if_true_or_pop", [%w[lit a], ["jump_if_true_or_pop", 2], ["lit", 1]]
  end

  # sabotage: loop while at != @program.size in Machine#run; the jump past
  # the end reads nil as an instruction and assert_answers's
  # assert_predicate fails.
  def test_a_jump_past_the_end_is_a_normal_halt
    assert_answers false, [["lit", false], ["jump_if_falsy_or_pop", 9], ["lit", 1]]
  end
end
