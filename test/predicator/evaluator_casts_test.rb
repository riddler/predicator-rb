# frozen_string_literal: true

require "test_helper"
require_relative "cast_helper"

# The cast opcode beyond what the corpus pins: its operand and stack rules,
# the number and duration forms it reads, and the forms it writes.
class EvaluatorCastsTest < Minitest::Test
  include CastHelper

  # sabotage: add "list" to Casts::TYPE_NAMES (and a cast_to_list answering
  # UNDEFINED); ["cast", "list"] runs and the second assert_fails's
  # refute_predicate fails.
  def test_an_operand_that_is_not_a_type_name_is_an_unknown_instruction
    assert_fails "EvaluationError", "unknown_instruction", [["lit", 1], %w[cast widget]]
    assert_fails "EvaluationError", "unknown_instruction", [["lit", 1], %w[cast list]]
    assert_fails "EvaluationError", "unknown_instruction", [["lit", 1], ["cast", 5]]
    assert_fails "EvaluationError", "unknown_instruction", [["lit", 1], ["cast"]]
    assert_fails "EvaluationError", "unknown_instruction", [["lit", 1], %w[cast Integer]]
  end

  # sabotage: drop the empty-stack guard in Casts#cast; the pop answers nil,
  # which casts to undefined, and assert_fails's refute_predicate fails.
  def test_an_empty_stack_is_insufficient_operands
    assert_fails "EvaluationError", "insufficient_operands", [%w[cast string]]
  end

  # sabotage: in Casts#cast, push value.to_s in place of UNDEFINED; the
  # first type name answers "Predicator::UNDEFINED" and assert_fails's
  # refute_predicate fails.
  def test_an_unbound_load_cast_to_any_type_is_still_an_unbound_variable_at_halt
    Predicator.const_get(:Evaluator).const_get(:Casts)::TYPE_NAMES.each do |type_name|
      error = assert_fails "UndefinedVariableError", "unbound_variable", [%w[load x], ["cast", type_name]]
      assert_equal "Undefined variable: x", error.message
    end
  end

  # sabotage: replace Integer(value, 10) with Integer(value) in
  # Casts#cast_to_integer; "010" reads as octal 8 and the first
  # assert_casts's assert_equal fails.
  def test_integer_text_is_decimal_of_any_size
    assert_casts "integer", "010" => 10, "-0" => 0, "1#{"0" * 30}" => 10**30
    ["", "-", "+1", "1_000", "0x10", "1.0", "١"].each { |text| assert_undefined(text, "integer") }
  end

  # sabotage: drop the CEILING check in FloatText.read; the first
  # text answers Infinity and its assert_undefined fails.
  def test_numbers_too_large_for_a_finite_float_are_undefined_and_too_small_ones_zero
    assert_undefined("17976931348623159#{"0" * 292}", "float")
    assert_equal 1.7976931348623157e308, cast("17976931348623158#{"0" * 292}", "float")
    assert_undefined(10**400, "float")
    assert_equal "-0.0", cast("-0.#{"0" * 400}1", "float").to_s
    assert_equal 5.0e-321, cast("0.#{"0" * 320}5", "float")
  end

  # sabotage: answer nil for "-0" in FloatText.read (when
  # magnitude.zero?); its assert_equal fails.
  def test_float_text_keeps_its_sign_and_reads_leading_zeros_and_nothing_but_a_decimal
    assert_equal "-0.0", cast("-0", "float").to_s
    assert_equal 12.5, cast("0012.50", "float")
    ["1.", ".5", "1e3", "+1.5", "1.5 ", "1_0.5"].each { |text| assert_undefined(text, "float") }
  end

  # sabotage: write a Float with value.to_s in Casts#cast_to_string; 1.0e20
  # writes "1.0e+20" and the first assert_equal fails.
  def test_a_float_is_written_as_the_reference_writes_one
    assert_equal "1.0e20", cast(1.0e20, "string")
    assert_equal "-0.0", cast(-0.0, "string")
    assert_equal "0.0001", cast(0.0001, "string")
    assert_equal(-2, cast(-2.9, "integer"))
    assert_equal 42.0, cast(42, "float")
  end

  # sabotage: write every unit in DurationText.write (drop the positive?
  # filter); a zero duration writes "0y0mo0w0d0h0m0s0ms" and the first
  # assert_equal fails.
  def test_a_duration_is_written_largest_unit_first_leaving_out_what_is_not_positive
    assert_equal "0s", cast(duration, "string")
    assert_equal "1y2mo3w4d5h6m7s8ms",
                 cast(duration(years: 1, months: 2, weeks: 3, days: 4, hours: 5, minutes: 6, seconds: 7,
                               milliseconds: 8), "string")
    assert_equal "0s", cast(duration(days: -3), "string")
    assert_equal "2h", cast(duration(days: -3, hours: 2), "string")
  end

  # sabotage: spend a fraction's remainder through weeks too (add :weeks to
  # DurationText::REMAINDER_UNITS); 0.5mo spends 2w1d and the
  # assert_casts's assert_equal for "0.5mo" fails.
  def test_a_fraction_is_spent_through_days_to_milliseconds
    assert_casts "duration",
                 "0.5mo" => duration(days: 15), "0.5y" => duration(days: 182, hours: 12),
                 "1.5w" => duration(weeks: 1, days: 3, hours: 12), "1.5m" => duration(minutes: 1, seconds: 30),
                 "2.25s" => duration(seconds: 2, milliseconds: 250), "1.000s" => duration(seconds: 1)
    assert_undefined("1.0001s", "duration")
  end

  # sabotage: replace the accumulation in DurationText.read with
  # `units[unit] = amount`; "1s2s" answers 2 seconds and the assert_casts's
  # assert_equal for "1s2s" fails.
  def test_duration_text_accumulates_repeated_units_and_reads_mo_and_ms_whole
    assert_casts "duration",
                 "1s2s" => duration(seconds: 3), "1mo2m" => duration(months: 1, minutes: 2),
                 "5ms1m" => duration(milliseconds: 5, minutes: 1), "1.5d0h" => duration(days: 1, hours: 12),
                 "#{10**20}y" => duration(years: 10**20)
    ["", "1", "d", "-1d", "1 d", "1D", ".5s", "1.s", "1d ", "1w2x"].each { |text| assert_undefined(text, "duration") }
  end

  # sabotage: drop the DURATION_KEYS check from Casts#cast_duration (read
  # any Hash with as_duration); {"a" => 1} writes "0s" and its
  # assert_undefined fails.
  def test_a_map_carrying_the_seven_units_is_a_duration_and_any_other_map_is_not
    units = { "years" => 0, "months" => 0, "weeks" => 0, "days" => 2, "hours" => 0, "minutes" => 0, "seconds" => 0 }
    assert_equal "2d", cast(units, "string")
    assert_same units, cast(units, "duration")
    assert_equal "2d5ms", cast(units.merge("milliseconds" => 5, "extra" => "x"), "string")
    assert_undefined({ "a" => 1 }, "string")
    assert_undefined(units.except("seconds"), "duration")
    assert_undefined(units.merge("days" => "2"), "string")
    assert_undefined(units, "integer")
  end

  # sabotage: let the duration's own units win in RichTypes#object_set
  # ({ key => value }.merge(target)); "days" set to 5 writes "3d" and the
  # first assert_equal fails.
  def test_a_unit_name_object_set_writes_on_a_duration_is_the_unit_the_cast_reads
    set = ->(key, value) { run_list([["duration", [[3, "d"]]], ["lit", value], ["object_set", key], %w[cast string]]) }
    assert_equal "5d", set.call("days", 5).value
    assert_equal "3d500ms", set.call("milliseconds", 500).value
    assert_equal "3d", set.call("note", 1).value
    assert_same Predicator::UNDEFINED, set.call("days", 2.5).value
  end
end
