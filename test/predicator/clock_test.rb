# frozen_string_literal: true

require "test_helper"

# The clock a run reads the time from: a bad one fails the run the same way
# on either path that reads it, a relative date and Date.now().
class ClockTest < Minitest::Test
  def described(error) = [error.type, error.reason]

  # A clock that answers something other than a DateTime, and one that
  # raises a StandardError.
  BAD_CLOCKS = { "answers 5" => -> { 5 }, "raises" => -> { raise "no time" } }.freeze

  # What a run answers, or the StandardError it raised in its place, so that
  # a raise fails an assertion rather than erroring the test.
  def answered(source, clock)
    Predicator.evaluate(source, {}, clock:)
  rescue StandardError => e
    e
  end

  # sabotage: drop `rescue ClockFault => e` and its `e.error` from
  # Machine#drive; "3d ago" raises the fault out of evaluate and the
  # assert_instance_of fails.
  def test_a_bad_clock_fails_a_relative_date_with_clock_failed
    BAD_CLOCKS.each do |what, clock|
      result = answered("3d ago", clock)

      assert_instance_of Predicator::Result, result, what
      assert_equal %w[EvaluationError clock_failed], described(result.error), what
    end
  end

  # sabotage: drop the `rescue ClockFault` re-raise from Calls#dispatch;
  # Date.now() reports the fault as a function that raised, and the
  # assert_equal on clock_failed fails.
  def test_a_bad_clock_fails_date_now_with_clock_failed
    BAD_CLOCKS.each do |what, clock|
      result = answered("Date.now()", clock)

      assert_instance_of Predicator::Result, result, what
      assert_equal %w[EvaluationError clock_failed], described(result.error), what
    end
  end

  # sabotage: rescue Exception rather than StandardError in
  # RichTypes#read_clock; the NoMemoryError becomes a failed result and the
  # first assert_raises fails.
  def test_a_clock_raising_an_exception_that_is_not_a_standard_error_propagates
    clock = -> { raise NoMemoryError, "no room" }

    assert_raises(NoMemoryError) { Predicator.evaluate("3d ago", {}, clock:) }
    assert_raises(NoMemoryError) { Predicator.evaluate("Date.now()", {}, clock:) }
  end
end
