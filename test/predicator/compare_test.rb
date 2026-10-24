# frozen_string_literal: true

require "test_helper"

# The compare opcode's answers, run through the evaluator: strict equality
# over every value, propagation of undefined and of a type-mismatched pair,
# null's four-row matrix, and the order of each type that has one.
class CompareTest < Minitest::Test
  EVALUATOR = Predicator.const_get(:Evaluator)
  UNDEFINED = Predicator::UNDEFINED

  def date(text) = Predicator::Date.new(**%i[year month day].zip(text.split("-").map(&:to_i)).to_h)
  def at(seconds, microsecond = 0) = Predicator::DateTime.new(epoch_seconds: seconds, microsecond:)

  def compare(left, operator, right)
    result = EVALUATOR.evaluate([["lit", left], ["lit", right], ["compare", operator]])

    assert_predicate result, :ok?, -> { "failed with #{result.error.inspect}" }
    result.value
  end

  def assert_compares(expected, left, operator, right)
    assert_same expected, compare(left, operator, right), "#{left.inspect} #{operator} #{right.inspect}"
  end

  # sabotage: answer UNDEFINED for every operator in Compare.call when
  # either side is undefined (move the undefined check above the strict
  # branches); undefined STRICT_EQ undefined answers undefined and the
  # first assert_compares fails.
  def test_strict_equality_answers_a_boolean_over_every_value
    assert_compares true, UNDEFINED, "STRICT_EQ", UNDEFINED
    assert_compares true, nil, "STRICT_EQ", nil
    assert_compares false, nil, "STRICT_EQ", UNDEFINED
    assert_compares true, UNDEFINED, "STRICT_NE", 1
  end

  # sabotage: compare with == alone in Compare.strict? (drop the
  # instance_of? half); 1 STRICT_EQ 1.0 answers true and the
  # assert_compares on it fails.
  def test_strict_equality_tells_integer_from_float_and_date_from_datetime
    assert_compares false, 1, "STRICT_EQ", 1.0
    assert_compares false, date("2024-01-15"), "STRICT_EQ", at(1_705_276_800)
    assert_compares true, [1, { "a" => [2.0] }], "STRICT_EQ", [1, { "a" => [2.0] }]
    assert_compares false, [1, { "a" => [2.0] }], "STRICT_EQ", [1, { "a" => [2] }]
    assert_compares false, { "a" => 1 }, "STRICT_EQ", { "b" => 1 }
  end

  # sabotage: make Compare.loose propagate undefined alone (replace its
  # peers? guard with an undefined? guard); null EQ null answers true and
  # that assert_compares fails.
  def test_undefined_null_and_a_mismatched_pair_propagate_under_the_other_operators
    assert_compares UNDEFINED, UNDEFINED, "EQ", UNDEFINED
    assert_compares UNDEFINED, nil, "EQ", nil
    assert_compares UNDEFINED, nil, "NE", UNDEFINED
    assert_compares UNDEFINED, true, "EQ", 1
    assert_compares UNDEFINED, 1, "GT", "a"
  end

  # sabotage: make Compare.kind answer :integer for an Integer; 1 == 1.0
  # becomes a mismatch and answers undefined, and the assert_compares fails.
  def test_loose_equality_bridges_integer_and_float
    assert_compares true, 1, "EQ", 1.0
    assert_compares true, 2, "LT", 2.5
    assert_compares false, 1, "NE", 1.0
  end

  # sabotage: order strings with casecmp in Order.peer_order; "B" < "a"
  # answers false and the first assert_compares fails.
  def test_strings_order_by_code_point_with_no_collation
    assert_compares true, "B", "LT", "a"
    assert_compares true, "z", "LT", "é"
    assert_compares true, "abc", "LT", "abd"
  end

  # sabotage: swap the 1 and 0 for booleans in Order.peer_order; false <
  # true answers false and the first assert_compares fails.
  def test_false_orders_before_true
    assert_compares true, false, "LT", true
    assert_compares true, true, "GTE", true
  end

  # sabotage: make Compare.instant answer [to_days, 0] for a date (days,
  # not seconds); the date sorts near the epoch and the mixed LT fails.
  def test_dates_and_datetimes_compare_by_instant_a_date_at_midnight_utc
    assert_compares true, date("2024-01-15"), "EQ", at(1_705_276_800)
    assert_compares true, date("2024-01-15"), "LT", at(1_705_276_801)
    assert_compares true, at(1_705_276_800, 1), "GT", at(1_705_276_800)
  end

  # sabotage: walk no members in Order.list_order (0.times); [1, 2] <
  # [1, 3] answers false and the first assert_compares fails.
  def test_lists_order_by_the_first_member_that_differs_then_by_length
    assert_compares true, [1, 2], "LT", [1, 3]
    assert_compares true, [1], "LT", [1, 2]
    assert_compares true, [date("2026-01-01"), date("2026-01-02")], "GT", [date("2026-01-01"), date("2025-12-31")]
    assert_compares UNDEFINED, [1], "LT", ["a"]
  end

  # sabotage: answer 1 for every null member in Order.null_against; null
  # against "a" orders after it and the assert_compares on it fails.
  def test_a_null_member_orders_after_a_number_and_false_and_before_the_rest
    assert_compares true, [nil], "GT", [1]
    assert_compares true, [nil], "GT", [false]
    assert_compares true, [nil], "LT", ["a"]
    assert_compares true, [true], "GT", [nil]
    assert_compares true, [nil, 1], "LT", [nil, 2]
  end

  # sabotage: drop the date_against_datetime? line from
  # Order.member_order; the pair at one instant steps level and the first
  # assert_compares fails.
  def test_a_date_member_orders_before_a_datetime_member
    assert_compares true, [date("2024-01-15")], "LT", [at(1_705_276_800)]
    assert_compares true, [at(0)], "GT", [date("2024-01-15")]
    assert_compares false, [date("2024-01-15")], "EQ", [at(1_705_276_800)]
  end

  # sabotage: answer nil for a level pair in Order.differing_order (`? nil :
  # nil`); the walk stops at the first pair and the assert_compares fails.
  def test_lists_of_maps_equal_by_instant_step_past_to_the_next_member
    assert_compares true, [[{ "a" => date("2024-01-15") }], 1], "LT", [[{ "a" => at(1_705_276_800) }], 2]
  end

  # sabotage: drop the size test from Compare.map_equal?; a map equals a
  # wider one holding its keys and the assert_compares on the wider map
  # fails.
  def test_maps_are_equal_by_key_and_member_and_have_no_order
    assert_compares true, { "a" => 1, "b" => 2 }, "EQ", { "b" => 2.0, "a" => 1 }
    assert_compares true, { "a" => 1 }, "NE", { "a" => 1, "b" => 2 }
    assert_compares true, { "a" => UNDEFINED }, "EQ", { "a" => UNDEFINED }
    assert_compares true, { "a" => 1 }, "NE", { "b" => 1 }
    assert_compares UNDEFINED, { "a" => 1 }, "LT", { "a" => 2 }
  end

  # sabotage: order durations by their days in Order.peer_order; the LT
  # answers true and the second assert_compares fails.
  def test_durations_are_equal_by_unit_and_have_no_order
    assert_compares true, Predicator::Duration.new(days: 1), "EQ", Predicator::Duration.new(days: 1)
    assert_compares UNDEFINED, Predicator::Duration.new(days: 1), "LT", Predicator::Duration.new(days: 2)
  end
end
