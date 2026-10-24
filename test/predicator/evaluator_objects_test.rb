# frozen_string_literal: true

require "test_helper"
require_relative "evaluator_helper"

# The object_new and object_set opcodes, and dates and instants inside the
# maps and lists a program builds.
class EvaluatorObjectsTest < Minitest::Test
  include EvaluatorHelper

  def instant(seconds, microsecond = 0) = Predicator::DateTime.new(epoch_seconds: seconds, microsecond:)

  def date(year, month, day) = Predicator::Date.new(year:, month:, day:)

  def answer(instructions, context = {})
    result = run_list(instructions, context)
    assert_predicate result, :ok?, -> { "failed with #{result.error.inspect}" }
    result.value
  end

  # The instructions that build the map {"a" => value}.
  def map_of(value) = [["object_new"], ["lit", value], %w[object_set a]]

  # The instructions that build the list of values.
  def list_of(*values) = values.map { |value| ["lit", value] } + [["make_list", values.size]]

  # sabotage: push `{ "" => 0 }` in place of `{}` from RichTypes#object_new;
  # the first assert_equal fails.
  def test_object_new_pushes_an_empty_map_and_object_set_writes_one_key
    assert_equal({}, answer([["object_new"]]))
    assert_equal({ "a" => { "b" => nil } },
                 answer([["object_new"], ["object_new"], ["lit", nil], %w[object_set b], %w[object_set a]]))
    assert_equal({ "a" => 2 }, answer(map_of(1) + [["lit", 2], %w[object_set a]]))
  end

  # sabotage: call `target.merge!` in place of `target.merge` in
  # RichTypes#object_set; the context's map gains the key and the
  # assert_equal on the context fails.
  def test_object_set_leaves_the_map_it_popped_unchanged
    context = { "x" => { "a" => 1 } }
    assert_equal({ "a" => 1, "b" => 2 }, answer([%w[load x], ["lit", 2], %w[object_set b]], context))
    assert_equal({ "x" => { "a" => 1 } }, context)
  end

  # sabotage: drop the stack-depth check from RichTypes#object_set; a lone
  # value pops nil as the map, answers invalid_stack_value, and the first
  # assert_fails's assert_equal fails.
  def test_object_set_checks_depth_then_takes_a_map_alone
    assert_fails "EvaluationError", "insufficient_operands", [["lit", 5], %w[object_set a]]
    assert_fails "EvaluationError", "insufficient_operands", [%w[object_set a]]
    [5, nil, Predicator::UNDEFINED, [1], date(2024, 1, 15), instant(0)].each do |target|
      assert_fails "EvaluationError", "invalid_stack_value", [["lit", target], ["lit", 1], %w[object_set a]]
    end
    assert_fails "EvaluationError", "invalid_stack_value", [%w[load missing], ["lit", 1], %w[object_set a]]
  end

  # sabotage: drop the line that reads a Duration target as its map in
  # RichTypes#object_set; the duration is refused and answer's
  # assert_predicate fails on the first call.
  def test_object_set_on_a_duration_answers_the_map_of_its_units
    units = %w[years months weeks days hours minutes seconds milliseconds].to_h { |name| [name, 0] }
    written = answer([["lit", Predicator::Duration.new(days: 2)], ["lit", 1], %w[object_set a]])
    assert_equal units.merge("days" => 2, "a" => 1), written
    assert_instance_of Hash, answer([["lit", Predicator::Duration.new], ["lit", 3], %w[object_set days]])
  end

  # Asserts each row [left, operator, right, expected], where left and right
  # are the instructions that build the two operands, answers expected.
  def assert_compares(rows)
    rows.each do |left, operator, right, expected|
      assert_equal expected, answer(left + right + [["compare", operator]]), "#{left} #{operator} #{right}"
    end
  end

  # sabotage: drop the date_against_datetime? refusal from
  # Compare.member_rule; a date member equals a datetime member at its
  # midnight and the third row's assert_equal fails.
  def test_dates_and_instants_in_built_maps_are_equal_by_value_and_have_no_order
    january = date(2024, 1, 15)
    assert_compares [
      [map_of(january), "EQ", map_of(january), true],
      [map_of(january), "EQ", map_of(date(2024, 1, 16)), false],
      [map_of(january), "EQ", map_of(instant(1_705_276_800)), false],
      [map_of(instant(0)), "LT", map_of(instant(1)), Predicator::UNDEFINED]
    ]
  end

  # sabotage: order chronological pairs in Order#peer_order by
  # `Compare.instant(right) <=> Compare.instant(left)`; the later date
  # member orders first and the first row's assert_equal fails.
  def test_dates_and_instants_in_built_lists_order_by_instant
    assert_compares [
      [list_of(date(2026, 1, 2)), "GT", list_of(date(2025, 12, 31)), true],
      [list_of(instant(5, 1)), "LT", list_of(instant(5, 2)), true],
      [list_of({ "a" => date(2024, 1, 15) }, 1), "LT", list_of({ "a" => instant(1_705_276_800) }, 2), true]
    ]
  end
end
