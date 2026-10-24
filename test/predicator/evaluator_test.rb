# frozen_string_literal: true

require "test_helper"
require_relative "evaluator_helper"

# The stack machine in expression mode: the halt rules, the instruction
# check, the load and its unbound policy, and the arguments a call takes.
# The opcodes are in evaluator_opcodes_test.rb and the comparison opcode's
# answers in compare_test.rb.
class EvaluatorTest < Minitest::Test
  include EvaluatorHelper

  # sabotage: make the empty-stack guard in Machine#halt `if false`; the run
  # answers ok with nil and assert_fails's refute_predicate fails.
  def test_an_empty_stack_at_halt_is_an_error
    assert_fails "EvaluationError", "empty_stack", []
  end

  # sabotage: answer @stack.first in Machine#halt; the run answers 1 and
  # assert_answers's assert_same fails.
  def test_the_answer_is_the_top_of_the_stack_and_the_rest_is_discarded
    assert_answers 2, [["lit", 1], ["lit", 2]]
  end

  # sabotage: drop the arity check from Machine#row_for and hand each handler
  # exactly its row's operand count; ["lit"] pushes nil and the first
  # assert_fails's refute_predicate fails.
  def test_an_instruction_of_the_wrong_length_is_unknown
    assert_fails "EvaluationError", "unknown_instruction", [["lit"]]
    assert_fails "EvaluationError", "unknown_instruction", [["lit", 1, 2]]
  end

  # sabotage: skip the operand-shape test in Machine#row_for (answer true);
  # ["load", 5] loads an unbound root and the assert_fails's assert_equal
  # on type and reason fails.
  def test_a_malformed_operand_is_an_unknown_instruction
    assert_fails "EvaluationError", "unknown_instruction", [["load", 5]]
    assert_fails "EvaluationError", "unknown_instruction", [["lit", 1], ["lit", 1], %w[compare FOO]]
    assert_fails "EvaluationError", "unknown_instruction", [["lit", true], ["jump_if_falsy_or_pop", 0]]
    assert_fails "EvaluationError", "unknown_instruction", [["lit", true], ["jump_if_true_or_pop", true]]
  end

  # sabotage: drop the Array guard from Machine#row_for; the map's #first
  # is a pair, not an opcode, so the first call still fails unknown, and
  # the String "lit" raises NoMethodError in #first, erroring the test (the
  # guard keeps a non-list from raising; no assertion runs before it).
  def test_an_instruction_that_is_not_a_list_or_names_no_opcode_is_unknown
    assert_fails "EvaluationError", "unknown_instruction", [{ "lit" => 1 }]
    assert_fails "EvaluationError", "unknown_instruction", ["lit"]
    assert_fails "EvaluationError", "unknown_instruction", [["no_such_opcode"]]
    assert_fails "EvaluationError", "unknown_instruction", [[]]
  end

  # sabotage: check the shape before retirement in Machine#step (drop the
  # by-name refusal, so row_for's arity check answers first); ["and", 1]
  # fails unknown and the first assert_fails's assert_equal fails.
  def test_a_retired_opcode_is_refused_as_retired
    assert_fails "EvaluationError", "retired_opcode", [["lit", true], ["and", 1]]
    assert_fails "EvaluationError", "retired_opcode", [["lit", true], ["lit", true], ["and"]]
    assert_fails "EvaluationError", "retired_opcode", [["lit", true], ["lit", true], ["or"]]
  end

  # sabotage: push UNDEFINED in Machine#load_root whatever the context
  # binds; the assert_answers on the bound null fails.
  def test_a_load_reads_what_the_context_binds_null_and_undefined_included
    assert_answers 7, [%w[load x]], { "x" => 7 }
    assert_answers nil, [%w[load x]], { "x" => nil }
    assert_answers Predicator::UNDEFINED, [%w[load x]], { "x" => Predicator::UNDEFINED }
  end

  # sabotage: make the unbound test in Machine#halt `&& false`; the run
  # answers undefined and assert_fails's refute_predicate fails.
  def test_undefined_from_an_unbound_root_at_halt_is_an_unbound_variable_error
    error = assert_fails "UndefinedVariableError", "unbound_variable", [%w[load x], %w[load y]]

    assert_match(/\bx\b/, error.message)
  end

  # sabotage: record the unbound root with @unbound = name (the last one,
  # not the first) in Machine#load_root; the message names y and the
  # assert_match on x fails.
  def test_the_error_names_the_first_root_found_unbound
    error = assert_fails "UndefinedVariableError", "unbound_variable",
                         [%w[load x], %w[load y], %w[compare EQ]]

    assert_match(/\bx\z/, error.message)
  end

  # sabotage: drop the UNDEFINED test from Machine#halt's unbound rule; the
  # false answer is rewritten into an error and assert_answers's
  # assert_predicate fails.
  def test_an_unbound_root_whose_undefined_is_not_the_answer_is_no_error
    assert_answers false, [%w[load x], ["lit", 1], %w[compare STRICT_EQ]]
    assert_answers false, [["lit", false], ["jump_if_falsy_or_pop", 2], %w[load x]]
  end

  # sabotage: make the :error policy guard in Machine#load_root `if false`;
  # the run answers false and assert_fails's refute_predicate fails.
  def test_the_error_policy_stops_at_the_load
    assert_fails "UndefinedVariableError", "unbound_variable",
                 [%w[load x], ["lit", 1], %w[compare STRICT_EQ]], on_unbound: :error
    assert_answers 1, [%w[load x]], { "x" => 1 }, on_unbound: :error
  end

  # sabotage: make the UNBOUND_POLICIES check in Evaluator.settings
  # `unless true`; the run answers and the first assert_raises fails.
  def test_arguments_of_the_wrong_kind_are_refused_as_a_callers_bug
    assert_raises(ArgumentError) { run_list([["lit", 1]], {}, on_unbound: :ignore) }
    assert_raises(ArgumentError) { run_list("lit", {}) }
    assert_raises(ArgumentError) { run_list([["lit", 1]], []) }
  end

  # sabotage: make the unbound rewrite in Machine#mismatch `&& false`; the
  # error is a TypeMismatchError and the first assert_fails's assert_equal
  # fails.
  def test_a_type_mismatch_over_an_unbound_roots_undefined_names_the_variable
    assert_fails "UndefinedVariableError", "unbound_variable", [%w[load x], ["not"]]
    assert_fails "TypeMismatchError", "logical_not", [%w[load x], ["not"]], { "x" => Predicator::UNDEFINED }
    assert_fails "TypeMismatchError", "unary_minus", [%w[load x], %w[lit a], ["unary_minus"]]
  end
end
