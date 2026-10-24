# frozen_string_literal: true

require "test_helper"
require_relative "evaluator_helper"

# The date rules of add and subtract: the duration between two dates or
# datetimes, and a date or a datetime moved by a duration.
class EvaluatorDateArithmeticTest < Minitest::Test
  include EvaluatorHelper

  def date(text) = Predicator::Date.new(**%i[year month day].zip(text.split("-").map(&:to_i)).to_h)

  def instant(seconds, microsecond = 0) = Predicator::DateTime.new(epoch_seconds: seconds, microsecond:)

  def duration(**units) = Predicator::Duration.new(**units)

  # Asserts each row [left, opcode, right, expected] answers expected.
  def assert_rows(rows)
    rows.each do |left, opcode, right, expected|
      result = run_list([["lit", left], ["lit", right], [opcode]])
      assert_predicate result, :ok?, -> { "#{left.inspect} #{opcode} #{right.inspect}: #{result.error.inspect}" }
      assert_equal expected, result.value, "#{left.inspect} #{opcode} #{right.inspect}"
    end
  end

  # sabotage: swap left and right in Chronology.difference's date clause;
  # the days answer -5 and the first row's assert_equal fails.
  def test_two_dates_or_datetimes_are_apart_by_a_duration
    assert_rows [
      [date("2024-01-15"), "subtract", date("2024-01-10"), duration(days: 5)],
      [instant(7200), "subtract", instant(0), duration(seconds: 7200)],
      [instant(0), "subtract", instant(1, 500_000), duration(seconds: -1)],
      [instant(86_400 * 2), "subtract", date("1970-01-02"), duration(seconds: 86_400)]
    ]
  end

  # sabotage: drop the time units from Chronology.whole_days, so it answers
  # date_days alone; 2024-01-10 + 2 days 25 hours answers 2024-01-12 and the
  # second row's assert_equal fails.
  def test_a_date_moves_by_whole_days_with_months_of_thirty_days
    assert_rows [
      [date("2024-01-08"), "add", duration(days: 3, weeks: 1), date("2024-01-18")],
      [date("2024-01-10"), "add", duration(days: 2, hours: 25), date("2024-01-13")],
      [duration(months: 1), "add", date("2024-01-31"), date("2024-03-01")],
      [date("2024-01-01"), "subtract", duration(years: 1), date("2023-01-01")],
      [date("2024-01-10"), "add", duration(milliseconds: 999), date("2024-01-10")]
    ]
  end

  # sabotage: drop the milliseconds term from Chronology.datetime_step;
  # 1500 milliseconds moves the instant by 1 second and the first row's
  # assert_equal fails.
  def test_a_datetime_moves_by_milliseconds_only_when_they_are_positive
    assert_rows [
      [instant(0), "add", duration(seconds: 1, milliseconds: 500), instant(1, 500_000)],
      [instant(0), "subtract", duration(milliseconds: 500), instant(-1, 500_000)],
      [instant(0), "add", duration(minutes: 1, milliseconds: -500), instant(60)]
    ]
  end

  # sabotage: drop the Duration-first clause from Arithmetic#shifted; a
  # duration plus a datetime is refused and the assert_rows's
  # assert_predicate fails.
  def test_a_duration_moves_a_date_from_either_side_of_add_but_only_the_right_of_subtract
    assert_rows [[duration(hours: 1), "add", instant(0), instant(3600)]]
    [date("2024-01-01"), duration(days: 1)].each do |right|
      assert_fails "TypeMismatchError", "subtract", [["lit", duration(days: 1)], ["lit", right], ["subtract"]]
    end
  end
end
