# frozen_string_literal: true

require "test_helper"
require_relative "evaluator_helper"

# jump, pop_jump_if_falsy and jump_backward with the loop budget, beyond
# what the corpus's cases pin.
class EvaluatorJumpsTest < Minitest::Test
  include EvaluatorHelper

  # i = 0; while i < limit { i = i + 1 }; i - one back edge per pass.
  def counted(limit)
    [%w[lit i], ["lit", 0], ["store", 1], %w[load i], ["lit", limit], %w[compare LT],
     ["pop_jump_if_falsy", 7], %w[lit i], %w[load i], ["lit", 1], ["add"], ["store", 1],
     ["jump_backward", 9], %w[load i]]
  end

  # sabotage: answer `at + offset + 1` in Statements#jump; the jump lands
  # one past the 2 and assert_answers's assert_same fails.
  def test_jump_goes_forward_and_past_the_end_is_a_halt
    assert_answers 2, [["lit", 1], ["jump", 2], ["lit", 9], ["lit", 2]]
    assert_answers 1, [["lit", 1], ["jump", 5]]
    assert_fails "EvaluationError", "unknown_instruction", [["lit", 1], ["jump", 0]]
    assert_fails "EvaluationError", "unknown_instruction", [["lit", 1], ["jump", 1.0]]
  end

  # sabotage: make Statements#pop_jump_if_falsy peek with `@stack.last`
  # instead of popping; the condition stays on the stack, the run answers
  # false, and the first assert_fails's refute_predicate fails.
  def test_pop_jump_if_falsy_pops_on_both_branches
    [false, nil, Predicator::UNDEFINED].each do |falsy|
      assert_answers 2, [["lit", falsy], ["pop_jump_if_falsy", 2], ["lit", 1], ["lit", 2]]
      assert_fails "EvaluationError", "empty_stack", [["lit", falsy], ["pop_jump_if_falsy", 1]]
    end
    assert_answers 1, [["lit", 0], ["lit", true], ["pop_jump_if_falsy", 2], ["lit", 1]]
    assert_fails "EvaluationError", "empty_stack", [["lit", true], ["pop_jump_if_falsy", 1]]
  end

  # sabotage: drop the `truth.nil?` refusal from
  # Statements#pop_jump_if_falsy; 0 jumps and the first assert_fails's
  # refute_predicate fails.
  def test_pop_jump_if_falsy_refuses_anything_but_a_boolean_null_or_undefined
    assert_fails "TypeMismatchError", "pop_jump_if_falsy", [["lit", 0], ["pop_jump_if_falsy", 1], ["lit", 1]]
    assert_fails "TypeMismatchError", "pop_jump_if_falsy", [%w[lit true], ["pop_jump_if_falsy", 1], ["lit", 1]]
    assert_fails "EvaluationError", "insufficient_operands", [["pop_jump_if_falsy", 1]]
    assert_answers 1, [%w[load nope], ["pop_jump_if_falsy", 2], ["lit", 2], ["lit", 1]]
  end

  # sabotage: make the budget check in Statements#jump_backward
  # `@budget.negative?`; a budget of 3 lets a fourth back edge through and
  # the budget-3 assert_fails's refute_predicate fails.
  def test_a_budget_of_n_lets_n_back_edges_through
    assert_answers 3, counted(3), loop_budget: 3
    assert_fails "EvaluationError", "loop_budget_exceeded", counted(4), loop_budget: 3
    assert_answers 0, counted(0), loop_budget: 0
    assert_fails "EvaluationError", "loop_budget_exceeded", counted(1), loop_budget: 0
  end

  # sabotage: set DEFAULT_LOOP_BUDGET to 9_999; the 10,000-pass loop is
  # refused and the first assert_answers's assert_predicate fails.
  def test_the_default_budget_is_ten_thousand_back_edges
    assert_answers 10_000, counted(10_000)
    assert_fails "EvaluationError", "loop_budget_exceeded", counted(10_001)
  end

  # sabotage: swap the two guards in Statements#jump_backward; the spent
  # budget answers first and the assert_fails's assert_equal fails.
  def test_a_target_before_the_start_is_unknown_whatever_the_budget
    assert_fails "EvaluationError", "unknown_instruction", [["lit", 1], ["jump_backward", 2]], loop_budget: 0
    assert_answers 7, [["lit", false], ["pop_jump_if_falsy", 2], ["jump_backward", 2], ["lit", 7]], loop_budget: 0
  end

  # sabotage: drop `!loop_budget.negative?` from Evaluator.settings; a
  # budget of -1 is taken and the first assert_raises fails.
  def test_a_loop_budget_that_is_not_a_count_is_a_callers_bug
    assert_raises(ArgumentError) { run_list([["lit", 1]], {}, loop_budget: -1) }
    assert_raises(ArgumentError) { run_list([["lit", 1]], {}, loop_budget: 1.0) }
    assert_raises(ArgumentError) { run_list([["lit", 1]], {}, budget: 1) }
    assert_raises(ArgumentError) { EVALUATOR.execute([["lit", 1]], {}, loop_budget: nil) }
  end
end
