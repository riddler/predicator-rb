# frozen_string_literal: true

require "test_helper"
require_relative "evaluator_helper"

# The duration and relative_date opcodes, the latter against an injected
# clock.
class EvaluatorDurationsTest < Minitest::Test
  include EvaluatorHelper

  NOON = Predicator::DateTime.new(epoch_seconds: 1_705_320_000, microsecond: 250_000)

  def duration(**units) = Predicator::Duration.new(**units)

  def instant(seconds, microsecond = 0) = Predicator::DateTime.new(epoch_seconds: seconds, microsecond:)

  def answer(instructions, context = {}, **)
    result = run_list(instructions, context, **)
    assert_predicate result, :ok?, -> { "failed with #{result.error.inspect}" }
    result.value
  end

  # A clock that answers NOON and counts how often it was read.
  def counting_clock
    reads = []
    clock = lambda do
      reads << :read
      NOON
    end
    [clock, reads]
  end

  # sabotage: map "min" to :hours in RichTypes::DURATION_UNITS; [1, "min"]
  # sets hours and the assert_equal for "min" fails.
  def test_duration_accepts_every_spelling_of_every_unit
    {
      years: %w[y year years], months: %w[mo month months], weeks: %w[w week weeks], days: %w[d day days],
      hours: %w[h hour hours], minutes: %w[m min minute minutes], seconds: %w[s sec second seconds],
      milliseconds: %w[ms millisecond milliseconds]
    }.each do |unit, spellings|
      spellings.each do |spelling|
        assert_equal duration(unit => 4), answer([["duration", [[4, spelling]]]]), spelling
      end
    end
  end

  # sabotage: accumulate in RichTypes#duration (units[unit] = (units[unit] ||
  # 0) + pair.first); [[1, "h"], [2, "hours"]] answers 3 hours and the first
  # assert_equal fails.
  def test_a_later_pair_overwrites_an_earlier_one_and_no_pair_is_zero
    assert_equal duration(hours: 2, days: -1), answer([["duration", [[1, "h"], [-1, "d"], [2, "hours"]]]])
    assert_equal duration, answer([["duration", []]])
  end

  # sabotage: drop `pair.size == 2` from RichTypes#unit_pair?; [3, "d", "h"]
  # sets 3 hours and its assert_fails's refute_predicate fails.
  def test_a_pair_that_is_not_an_integer_and_a_string_is_invalid_duration_format
    [["bad"], [3, "d", "h"], [1.5, "d"], [true, "d"], %w[3 d], [3, :d], "3d", nil].each do |pair|
      assert_fails "EvaluationError", "invalid_duration_format", [["duration", [[1, "d"], pair]]]
    end
  end

  # sabotage: swap the two checks in RichTypes#duration so the unit is read
  # first; [[3, "xyz"], ["bad"]] still fails on the unit, but [["bad"]]
  # reads "bad" as its unit, answers invalid_duration_unit, and the second
  # assert_fails's assert_equal fails.
  def test_an_unknown_unit_is_invalid_duration_unit_and_the_first_bad_pair_decides
    assert_fails "EvaluationError", "invalid_duration_unit", [["duration", [[3, "xyz"], ["bad"]]]]
    assert_fails "EvaluationError", "invalid_duration_format", [["duration", [["bad"], [3, "xyz"]]]]
    assert_fails "EvaluationError", "invalid_duration_unit", [["duration", [[3, "D"]]]]
  end

  # sabotage: give relative_date's row in Evaluator::INSTRUCTIONS the
  # operand shape :value; a direction of 1 answers invalid_direction and the
  # third assert_fails's assert_equal fails.
  def test_malformed_operands_are_unknown_instructions
    assert_fails "EvaluationError", "unknown_instruction", [%w[duration 3d]]
    assert_fails "EvaluationError", "unknown_instruction", [["duration"]]
    assert_fails "EvaluationError", "unknown_instruction", [["duration", [[1, "d"]]], ["relative_date", 1]]
    assert_fails "EvaluationError", "unknown_instruction", [["object_new"], ["lit", 1], ["object_set", 1]]
    assert_fails "EvaluationError", "unknown_instruction", [%w[object_new a]]
  end

  # sabotage: swap -1 and 1 for "ago" in RichTypes::DIRECTIONS; ago answers
  # NOON plus three days and the "ago" assert_equal fails.
  def test_relative_date_moves_the_injected_now_back_or_forward
    clock = -> { NOON }
    three_days = 3 * 86_400
    { "ago" => -three_days, "last" => -three_days, "future" => three_days, "next" => three_days }.each do |way, by|
      moved = answer([["duration", [[3, "d"]]], ["relative_date", way]], now: clock)
      assert_equal instant(NOON.epoch_seconds + by, 250_000), moved, way
    end
  end

  # sabotage: pass `moved.with(milliseconds: 0)` to Chronology.shift in
  # RichTypes#relative_date; one second and 500 milliseconds moves NOON by one
  # second and the first assert_equal fails.
  def test_relative_date_keeps_milliseconds_as_add_and_subtract_do
    clock = -> { NOON }
    assert_equal instant(NOON.epoch_seconds + 1, 750_000),
                 answer([["duration", [[1, "s"], [500, "ms"]]], %w[relative_date future]], now: clock)
    assert_equal instant(NOON.epoch_seconds - 3600, 250_000),
                 answer([["duration", [[1, "h"], [-5, "ms"]]], %w[relative_date ago]], now: clock)
  end

  # sabotage: drop `return @now if @now` from RichTypes#now; the clock is read
  # twice and the assert_equal on the read count fails.
  def test_the_clock_is_read_once_per_evaluation_and_only_when_asked
    clock, reads = counting_clock
    both = answer([["duration", [[1, "d"]]], %w[relative_date ago], ["duration", [[1, "d"]]],
                   %w[relative_date next], %w[compare LT]], now: clock)

    assert(both)
    assert_equal [:read], reads
    answer([["lit", 1]], now: clock)
    assert_equal [:read], reads
  end

  # sabotage: divide by 1_000 in place of 1_000_000 for epoch_seconds in
  # Evaluator::SYSTEM_CLOCK; the instant lands far past now and the
  # assert_includes fails.
  def test_with_no_clock_the_system_clock_answers
    before = Time.now.to_r
    moved = answer([["duration", []], %w[relative_date future]])
    after = Time.now.to_r

    assert_instance_of Predicator::DateTime, moved
    assert_includes (before.floor..after.ceil), moved.epoch_seconds + Rational(moved.microsecond, 1_000_000)
  end

  # sabotage: drop the respond_to?(:call) check from Evaluator.evaluate;
  # NOON is accepted as the clock and the first assert_raises fails.
  def test_a_clock_of_the_wrong_kind_is_a_callers_bug
    assert_raises(ArgumentError) { run_list([["lit", 1]], now: NOON) }
    error = assert_raises(ArgumentError) do
      run_list([["duration", [[1, "d"]]], %w[relative_date ago]], now: -> { Time.at(0) })
    end
    assert_match(/not a Predicator::DateTime/, error.message)
  end
end
