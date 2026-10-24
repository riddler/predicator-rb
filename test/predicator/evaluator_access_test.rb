# frozen_string_literal: true

require "test_helper"
require_relative "evaluator_helper"

# Member and index access, membership and list construction: what each
# target takes as a key, what misses, and what is refused.
class EvaluatorAccessTest < Minitest::Test
  include EvaluatorHelper

  U = Predicator::UNDEFINED

  def answer(instructions, context = {})
    result = run_list(instructions, context)
    assert_predicate result, :ok?, -> { "failed with #{result.error.inspect}" }
    result.value
  end

  # sabotage: replace `target.fetch(key, UNDEFINED)` with `target[key]` in
  # Machine#member; a missing key answers nil and the second assert_same
  # fails.
  def test_access_reads_a_member_and_a_miss_is_undefined_not_null
    assert_equal 1, answer([%w[load a], %w[access b]], { "a" => { "b" => 1 } })
    assert_same U, answer([%w[load a], %w[access c]], { "a" => { "b" => 1 } })
    assert_nil answer([%w[load a], %w[access b]], { "a" => { "b" => nil } })
  end

  # sabotage: change Machine#member's else branch to `target`; null.b
  # answers nil and the first assert_same fails.
  def test_access_on_anything_but_a_map_or_a_duration_is_undefined
    [nil, 5, "ab", [1, 2], true, Predicator::Date.new(year: 2024, month: 1, day: 1)].each do |target|
      assert_same U, answer([["lit", target], %w[access b]])
    end
  end

  # sabotage: drop the Duration clause from Machine#member; d.days answers
  # undefined and the first assert_equal fails.
  def test_a_duration_answers_its_eight_units_and_misses_on_any_other_name
    duration = Predicator::Duration.new(days: 21, milliseconds: 5)
    assert_equal 21, answer([["lit", duration], %w[access days]])
    assert_equal 5, answer([["lit", duration], %w[access milliseconds]])
    assert_same U, answer([["lit", duration], %w[access hash]])
    assert_equal 21, answer([["lit", duration], %w[lit days], ["bracket_access"]])
    assert_same U, answer([["lit", duration], ["lit", 1], ["bracket_access"]])
  end

  # sabotage: drop `key.negative? ||` from Machine#list_index; items[-1]
  # reads from the end and the second assert_same fails.
  def test_a_list_takes_a_non_negative_integer_and_misses_past_either_end
    assert_equal 20, answer([["lit", [10, 20]], ["lit", 1], ["bracket_access"]])
    assert_same U, answer([["lit", [10, 20]], ["lit", -1], ["bracket_access"]])
    assert_same U, answer([["lit", [10, 20]], ["lit", 2], ["bracket_access"]])
  end

  # sabotage: change Machine#list_index's guard to `key.is_a?(Numeric)`;
  # [1][1.5] misses past the end and the assert_fails's refute_predicate
  # for the key 1.5 fails.
  def test_a_list_refuses_any_other_key
    [%w[lit 0], ["lit", true], ["lit", U], ["lit", 1.5]].each do |key|
      assert_fails "TypeMismatchError", "bracket_access", [["lit", [1]], key, ["bracket_access"]]
    end
  end

  # sabotage: drop the ATOM_KEYS clause from Machine#map_key; m[true] is
  # refused and the answer helper's assert_predicate fails.
  def test_a_map_takes_strings_integers_booleans_null_and_undefined_as_keys
    map = { "a" => 1, 2 => "two", true => "yes" }
    assert_equal 1, answer([["lit", map], %w[lit a], ["bracket_access"]])
    assert_equal "two", answer([["lit", map], ["lit", 2], ["bracket_access"]])
    assert_equal "yes", answer([["lit", map], ["lit", true], ["bracket_access"]])
    [false, nil, U, "b"].each do |key|
      assert_same U, answer([["lit", map], ["lit", key], ["bracket_access"]])
    end
  end

  # sabotage: replace Machine#map_key's guard with `true`; m[1.5] misses and
  # the first assert_fails's refute_predicate fails.
  def test_a_map_a_date_and_a_datetime_refuse_any_other_key
    date = Predicator::Date.new(year: 2024, month: 1, day: 1)
    [{ "a" => 1 }, date, Predicator::DateTime.new(epoch_seconds: 0)].each do |target|
      [1.5, [1], { "a" => 1 }, date].each do |key|
        assert_fails "TypeMismatchError", "bracket_access", [["lit", target], ["lit", key], ["bracket_access"]]
      end
    end
    assert_same U, answer([["lit", date], %w[lit year], ["bracket_access"]])
  end

  # sabotage: change bracket_access's else branch to `map_key(at, target,
  # key)`; nil[1.5] is refused and the answer helper's assert_predicate
  # fails.
  def test_any_other_target_is_undefined_whatever_the_key
    [nil, 5, "ab", true].each do |target|
      assert_same U, answer([["lit", target], ["lit", 1.5], ["bracket_access"]])
    end
  end

  # sabotage: change Machine#bracket_access's depth check to
  # `@stack.empty?`; one operand pops nil as the target, answers
  # undefined, and the second assert_fails's refute_predicate fails.
  def test_too_few_operands_is_an_evaluation_error
    assert_fails "EvaluationError", "insufficient_operands", [%w[access a]]
    assert_fails "EvaluationError", "insufficient_operands", [["lit", [1]], ["bracket_access"]]
    assert_fails "EvaluationError", "insufficient_operands", [["lit", [1]], ["in"]]
    assert_fails "EvaluationError", "insufficient_operands", [["lit", 1], ["make_list", 2]]
  end

  # sabotage: swap `[right, left]` and `[left, right]` in
  # Machine#membership; 2 in [1, 2] is refused and the answer helper's
  # assert_predicate fails.
  def test_in_and_contains_find_a_member_by_loose_equality
    assert_same true, answer([["lit", 2], ["lit", [1, 2]], ["in"]])
    assert_same true, answer([["lit", [1, 2]], ["lit", 2.0], ["contains"]])
    assert_same false, answer([["lit", 3], ["lit", [1, 2]], ["in"]])
    assert_same true, answer([["lit", nil], ["lit", [nil]], ["in"]])
    assert_same true, answer([["lit", Predicator::Date.new(year: 1970, month: 1, day: 2)],
                              ["lit", [Predicator::DateTime.new(epoch_seconds: 86_400)]], ["in"]])
    assert_same true, answer([["lit", [1, [2]]], ["lit", [2.0]], ["contains"]])
  end

  # sabotage: drop the undefined check from Machine#membership; undefined in
  # [undefined] answers false and the first assert_same fails.
  def test_undefined_on_either_side_answers_undefined
    assert_same U, answer([["lit", U], ["lit", [U]], ["in"]])
    assert_same U, answer([["lit", U], %w[lit notalist], ["in"]])
    assert_same U, answer([["lit", [1]], ["lit", U], ["contains"]])
  end

  # sabotage: change Machine#membership's guard to `list.is_a?(Enumerable)`;
  # a map on the list side is searched and the second assert_fails's
  # refute_predicate fails.
  def test_the_list_side_must_be_a_list
    assert_fails "TypeMismatchError", "in", [["lit", 1], %w[lit x], ["in"]]
    assert_fails "TypeMismatchError", "contains", [["lit", { "a" => 1 }], ["lit", 1], ["contains"]]
  end

  # sabotage: change Machine#make_list's `@stack.pop(count)` to
  # `@stack.pop(count).reverse`; [a, b, c] answers [3, 2, 1] and the first
  # assert_equal fails.
  def test_make_list_pushes_its_count_of_values_in_source_order
    assert_equal [1, 2, 3], answer([["lit", 1], ["lit", 2], ["lit", 3], ["make_list", 3]])
    assert_equal [[], 9], answer([["lit", 9], ["make_list", 0], ["lit", 9], ["make_list", 2]])
  end

  # sabotage: drop `operand.is_a?(Integer) &&` from the count shape in
  # Evaluator::SHAPES; make_list 1.0 runs and answers insufficient operands,
  # and the second assert_fails's assert_equal fails.
  def test_malformed_operands_are_unknown_instructions
    assert_fails "EvaluationError", "unknown_instruction", [["make_list", -1]]
    assert_fails "EvaluationError", "unknown_instruction", [["make_list", 1.0]]
    assert_fails "EvaluationError", "unknown_instruction", [["lit", {}], ["access", 1]]
    assert_fails "EvaluationError", "unknown_instruction", [["lit", 1], ["lit", 2], ["add", 3]]
  end
end
