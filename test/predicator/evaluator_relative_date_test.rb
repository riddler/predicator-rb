# frozen_string_literal: true

require "test_helper"
require_relative "evaluator_helper"

# What relative_date takes from the stack, and the order of its refusals.
class EvaluatorRelativeDateTest < Minitest::Test
  include EvaluatorHelper

  NOON = Predicator::DateTime.new(epoch_seconds: 1_705_320_000, microsecond: 250_000)

  def instant(seconds, microsecond = 0) = Predicator::DateTime.new(epoch_seconds: seconds, microsecond:)

  def answer(instructions, **)
    result = run_list(instructions, {}, **)
    assert_predicate result, :ok?, -> { "failed with #{result.error.inspect}" }
    result.value
  end

  # sabotage: read each unit as `value.fetch(name.to_sym, 0)` in
  # RichTypes#as_duration; the map's string-keyed units read as zero and the
  # first assert_equal fails.
  def test_relative_date_reads_a_plain_map_by_its_unit_names
    clock = -> { NOON }
    moved = ->(map, way) { answer([["lit", map], ["relative_date", way]], clock:) }
    assert_equal instant(NOON.epoch_seconds + 86_400 + 60, 250_000),
                 moved.call({ "days" => 1, "minutes" => 1, "x" => "ignored" }, "future")
    assert_equal instant(NOON.epoch_seconds - 1, 750_000), moved.call({ "milliseconds" => 500, "seconds" => 0 }, "ago")
    assert_equal NOON, answer([["object_new"], %w[relative_date next]], clock:)
  end

  # sabotage: check the direction before the popped value in
  # RichTypes#relative_date; 3 on the stack answers invalid_direction and the
  # first row's assert_fails's assert_equal fails.
  def test_relative_date_checks_depth_then_the_duration_then_the_direction
    clock = -> { NOON }
    assert_fails("EvaluationError", "insufficient_operands", [%w[relative_date sideways]], clock:)
    [3, NOON, Predicator::Date.new(year: 2024, month: 1, day: 15), { "days" => "1" }, { "hours" => 1.5 }].each do |top|
      assert_fails("EvaluationError", "invalid_stack_value", [["lit", top], %w[relative_date sideways]], clock:)
    end
    assert_fails("EvaluationError", "invalid_direction", [["duration", []], %w[relative_date sideways]], clock:)
    assert_fails("EvaluationError", "invalid_direction", [["duration", []], %w[relative_date AGO]], clock:)
  end
end
