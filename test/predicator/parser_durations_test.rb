# frozen_string_literal: true

require "test_helper"
require_relative "parser_helper"

# Duration literals and relative dates: the units a literal keeps, a
# fraction expanded as the reference expands it, and the words that make a
# duration a date.
class ParserDurationsTest < Minitest::Test
  include ParserHelper

  # sabotage: keep the whole part even when it is zero in
  # Durations#fraction_units (drop `value.whole.positive? ?`, keeping
  # `[[value.whole, unit]]`); `0.5h` reads as [0, "h"], [30, "m"] and the
  # assert_trees fails.
  def test_a_duration_keeps_its_written_units_and_expands_a_fraction_as_the_reference_does
    assert_trees({
                   "3d8h2d" => duration([3, "d"], [8, "h"], [2, "d"]), "0.5h" => duration([30, "m"]),
                   "1.5s" => duration([1, "s"], [500, "ms"]), "0.5y" => duration([182, "d"], [12, "h"]),
                   "0.5mo" => duration([15, "d"]), "0.0d" => duration([0, "d"]),
                   "2w1.5d" => duration([2, "w"], [1, "d"], [12, "h"])
                 })
  end

  # sabotage: name the last repeated unit rather than the first (`.max`
  # for `.min` in Durations#repeated); `m` is named for `h` and the
  # assert_refusals fails.
  def test_an_inexact_fraction_and_a_unit_named_twice_after_an_expansion_are_refused
    assert_refusals({
                      "x + 1.5d1.5h2m2h" => ["duration_unit_twice",
                                             "Duration literal names the 'h' unit twice after expanding a fraction",
                                             [1, 5], [1, 5], [1, 17]],
                      "1d1.0005s2h" => ["duration_fraction", "Duration fraction is not a whole number of " \
                                                             "milliseconds: 1.0005s", [1, 3], [1, 3], [1, 10]]
                    })
  end

  # sabotage: answer :future for `ago` (swap the two directions in
  # Durations#direction); the assert_trees fails.
  def test_a_duration_with_a_direction_or_after_next_or_last_is_a_relative_date
    assert_trees({
                   "3d ago" => [:relative_date, duration([3, "d"]), :ago],
                   "2w1d from now" => [:relative_date, duration([2, "w"], [1, "d"]), :future],
                   "next 1mo" => [:relative_date, duration([1, "mo"]), :next],
                   "last (2d)" => [:relative_date, duration([2, "d"]), :last]
                 })
  end

  # sabotage: span a relative date from its word
  # (`between(start_of(word), end_of(last))` for `reaching(duration,
  # last)` in Durations#direction); the first assert_located fails.
  def test_a_relative_date_is_positioned_at_its_word_and_spans_its_duration
    assert_located("2w1d from now", { [] => [[1, 6], [1, 1], [1, 14]], [:duration] => [[1, 1], [1, 1], [1, 5]] })
    assert_located("next 1mo", { [] => [[1, 1], [1, 1], [1, 9]], [:duration] => [[1, 6], [1, 6], [1, 9]] })
  end

  # sabotage: accept any primary after `next` (drop the Ast::Duration test
  # in Primaries#relative_date, answering a relative date over it); the
  # assert_refusals flunks.
  def test_next_and_last_take_a_bare_duration_and_from_takes_now
    assert_refusals({
                      "next 3d ago" => ["expected_duration", "Expected duration after 'next' but found number '3'",
                                        [1, 6], [1, 6], [1, 7]],
                      "last x" => ["expected_duration", "Expected duration after 'last' but found identifier 'x'",
                                   [1, 6], [1, 6], [1, 7]],
                      "1d from" => ["expected_now", "Expected 'now' after 'from' but found end of input", [1, 8],
                                    [1, 8], [1, 8]]
                    })
  end
end
