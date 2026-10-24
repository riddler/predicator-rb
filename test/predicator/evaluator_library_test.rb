# frozen_string_literal: true

require "test_helper"
require_relative "evaluator_helper"

# The library's string, list, date and math functions, beyond what the
# corpus's cases pin.
class EvaluatorLibraryTest < Minitest::Test
  include EvaluatorHelper

  def call(name, *args, **) = run_list([*args.map { |arg| ["lit", arg] }, ["call", name, args.size]], {}, **)

  def value(name, *, **)
    result = call(name, *, **)
    assert_predicate result, :ok?, -> { "failed with #{result.error.inspect}" }
    result.value
  end

  def refused(name, *)
    result = call(name, *)
    refute_predicate result, :ok?, -> { "answered #{result.value.inspect}" }
    result.error.reason
  end

  COMBINING = "José x" # six grapheme clusters, eight bytes

  # sabotage: count `value.chars.size` in Library#string_len; the combining
  # mark counts as its own character and the first assert_equal fails.
  def test_a_length_and_a_substring_count_grapheme_clusters
    assert_equal 6, value("len", COMBINING)
    assert_equal 8, value("len", "ab\r\ncdefg")
    assert_equal "x", value("substring", COMBINING, 5)
    assert_equal "José", value("substring", COMBINING, 0, 4)
  end

  # sabotage: answer `value.index(sub)` in Library#string_index_of; the
  # offset counts characters and the first assert_equal fails.
  def test_index_of_answers_a_byte_offset
    assert_equal 7, value("index_of", COMBINING, "x")
    assert_equal 0, value("index_of", "abc", "")
    assert_equal(-1, value("index_of", "", "a"))
  end

  # sabotage: trim with `value.strip` in Library#string_trim; the next-line
  # character stays and the first assert_equal fails.
  def test_trim_removes_white_space_by_its_unicode_property
    assert_equal "a b", value("trim", "\u0085　 a b\t\n")
    assert_equal "﻿a﻿", value("trim", "﻿a﻿")
  end

  # sabotage: drop the `|| []` in Library#string_substring; a start past
  # the end slices nil, the call raises, and value's assert_predicate
  # fails.
  def test_a_substring_past_the_end_answers_what_the_string_has
    assert_equal "", value("substring", "ab", 3)
    assert_equal "b", value("substring", "ab", 1, 9)
  end

  # sabotage: call substring_signs before substring_types in
  # Library#string_substring; ("x", -1, "y") answers the non-negative
  # sentence and the third assert_equal fails.
  def test_substring_refusals_name_what_they_wanted
    assert_equal "substring() expects a non-negative start index", refused("substring", "x", -1)
    assert_equal "substring() expects a non-negative start index and length", refused("substring", "x", 0, -1)
    assert_equal "substring() expects a string, an integer start index, and an integer length",
                 refused("substring", "x", -1, "y")
    assert_equal "substring() expects a string and an integer start index", refused("substring", 1, 0)
  end

  # sabotage: read the shape as `two = length.compact.empty?` in
  # Library#string_substring; a null length is read as the two-argument
  # call, answers that call's sentence, and the assert_equal fails.
  def test_a_null_length_is_a_length_that_is_not_an_integer
    three = "substring() expects a string, an integer start index, and an integer length"
    assert_equal([three] * 3, [["abc", 0], [1, 0], ["abc", -1]].map { |args| refused("substring", *args, nil) })
  end

  # sabotage: drop the second String check in Library#two_strings; a
  # Integer prefix reaches start_with? and the first assert_equal reads a
  # raised TypeError's sentence instead.
  def test_string_functions_refuse_what_is_not_a_string
    assert_equal "starts_with() expects two string arguments", refused("starts_with", "x", 1)
    assert_equal "ends_with() expects two string arguments", refused("ends_with", 1, "x")
    assert_equal "index_of() expects two string arguments", refused("index_of", "x", nil)
    assert_equal "upper() expects a string argument", refused("upper", 1)
    assert_equal "lower() expects a string argument", refused("lower", [])
    assert_equal "trim() expects a string argument", refused("trim", nil)
    assert_equal "concat() expects two list arguments", refused("concat", [1], 2)
  end

  # sabotage: drop `.to_date` in Library#civil_date; a DateTime has no
  # year, the call raises, and value's assert_predicate fails.
  def test_the_date_functions_read_a_datetime_in_utc
    last = Predicator::DateTime.new(epoch_seconds: 1_704_067_199) # 2023-12-31T23:59:59Z
    assert_equal([2023, 12, 31], %w[Date.year Date.month Date.day].map { |name| value(name, last) })
    assert_equal "Date.month() expects a date or datetime argument", refused("Date.month", "2024-01-01")
  end

  # sabotage: answer `@clock.call` in Library#date_now; the clock is asked
  # twice and the count assert_equal fails.
  def test_date_now_reads_the_evaluations_clock_once
    asked = 0
    instant = Predicator::DateTime.new(epoch_seconds: 86_400)
    clock = lambda {
      asked += 1
      instant
    }
    both = run_list([["call", "Date.now", 0], ["call", "Date.now", 0], ["make_list", 2]], clock:)
    assert_equal [instant, instant], both.value
    assert_equal 1, asked
  end

  # sabotage: answer `base**exponent` for every Integer pair in
  # MathFunctions#math_pow; 2 ** -2 answers a Rational and the first
  # assert_same fails.
  def test_pow_keeps_integers_exact_only_for_a_non_negative_exponent
    assert_same 0.25, value("Math.pow", 2, -2)
    assert_equal 2**100, value("Math.pow", 2, 100)
    assert_equal "Math.pow has no finite real answer for 0 and -1", refused("Math.pow", 0, -1)
    assert_equal "Math.pow expects two numeric arguments", refused("Math.pow", "2", 1)
  end

  # sabotage: drop the Integer branch in MathFunctions#math_sqrt (`if
  # false`); 2**80 answers a Float and the assert_kind_of fails.
  def test_sqrt_is_exact_for_an_integer_square
    root = value("Math.sqrt", 2**80)
    assert_kind_of Integer, root
    assert_equal 2**40, root
    assert_same 1.5, value("Math.sqrt", 2.25)
    assert_equal "Math.sqrt expects a numeric argument", refused("Math.sqrt", "4")
  end

  # sabotage: round with `value.round(half: :even)` in
  # MathFunctions#math_round; 2.5 answers 2 and the first assert_same fails.
  def test_rounding_answers_integers
    assert_same 3, value("Math.round", 2.5)
    assert_same(-3, value("Math.floor", -2.5))
    assert_same(-2, value("Math.ceil", -2.5))
    assert_same 4, value("Math.floor", 4)
    assert_same 1.5, value("Math.abs", -1.5)
    assert_equal "Math.abs expects a numeric argument", refused("Math.abs", true)
  end

  # sabotage: answer `[right, left].min` in MathFunctions#math_min; equal
  # numbers answer the second and the first assert_same fails.
  def test_min_and_max_answer_the_first_of_two_equal_numbers
    assert_same 1.0, value("Math.min", 1.0, 1)
    assert_same 1, value("Math.max", 1, 1.0)
    assert_equal "Math.max expects two numeric arguments", refused("Math.max", 1, nil)
  end

  # sabotage: answer `Random.new.rand(2)` in MathFunctions#math_random; an
  # Integer answers and the assert_kind_of fails.
  def test_random_answers_a_float_below_one
    drawn = value("Math.random")
    assert_kind_of Float, drawn
    assert_includes 0.0...1.0, drawn
  end
end
