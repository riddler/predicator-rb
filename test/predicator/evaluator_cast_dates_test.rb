# frozen_string_literal: true

require "test_helper"
require_relative "cast_helper"

# The ISO 8601 text the `::date` and `::datetime` casts read, at the edges
# the corpus does not pin.
class EvaluatorCastDatesTest < Minitest::Test
  include CastHelper

  # sabotage: drop the `year = -year` line in IsoText.civil_date;
  # "-2026-08-09" reads as year 2026 and the second assert_equal fails.
  def test_a_date_text_may_sign_its_year_and_must_name_a_real_date
    assert_equal date(2026, 8, 9), cast("+2026-08-09", "date")
    assert_equal date(-2026, 8, 9), cast("-2026-08-09", "date")
    assert_equal "-2026-08-09", cast(date(-2026, 8, 9), "string")
    assert_equal date(2024, 2, 29), cast("2024-02-29", "date")
    ["2026-02-29", "20260809", "2026-8-9", "12026-08-09", "2026-08-09T00:00:00Z", "2026-08-09 "].each do |text|
      assert_undefined(text, "date")
    end
  end

  # sabotage: return 0 for every zone in IsoText.read_offset; "+05:30"
  # reads as UTC and the assert_casts's assert_equal for it fails.
  def test_a_datetime_text_reads_each_offset_spelling_as_the_instant_it_names
    at = "2026-08-09T10:00:00"
    assert_casts "datetime",
                 "#{at}+05:30" => instant("2026-08-09T04:30:00"), "#{at}+0530" => instant("2026-08-09T04:30:00"),
                 "#{at}+05" => instant("2026-08-09T05:00:00"), "#{at}-05:45" => instant("2026-08-09T15:45:00"),
                 "#{at}+23:59" => instant("2026-08-08T10:01:00"), "#{at}-0000" => instant(at),
                 "#{at}-00" => instant(at), "#{at}Z" => instant(at)
  end

  # sabotage: drop the "-00:00" refusal in IsoText.read_offset; that text
  # reads as UTC and its assert_undefined fails.
  def test_offsets_the_reference_refuses_are_undefined
    %w[-00:00 +24:00 +05:60 +5:30 +05:30:00 z].each do |zone|
      assert_undefined("2026-08-09T10:00:00#{zone}", "datetime")
    end
    assert_undefined("2026-08-09T10:00:00", "datetime")
  end

  # sabotage: let each offset field take a sign (`[-0-9][0-9]` for
  # `[0-9]{2}` in the offset of IsoText::DATETIME_TEXT and in
  # IsoText::OFFSET_TEXT); "+-5:30" reads as an instant and its
  # assert_undefined fails.
  def test_an_offset_field_carrying_a_sign_is_undefined
    %w[+-5:30 +05:-3 +-530 +-5].each do |zone|
      assert_undefined("2026-08-09T10:00:00#{zone}", "datetime")
    end
  end

  # sabotage: read three fraction digits in IsoText.local_instant ([0, 3]
  # for [0, 6], padded back to six); ".1234567" reads 123000 microseconds
  # and the first assert_equal fails.
  def test_a_datetime_text_reads_its_fraction_to_the_microsecond_and_its_separators
    assert_equal "2026-08-09T10:00:00.123456Z", cast(cast("2026-08-09T10:00:00.1234567Z", "datetime"), "string")
    assert_equal "2026-08-09T10:00:00.500000Z", cast(cast("2026-08-09T10:00:00,5Z", "datetime"), "string")
    assert_equal instant("2026-08-09T10:00:00"), cast("2026-08-09 10:00:00Z", "datetime")
    assert_equal instant("2026-08-09T10:00:00"), cast("+2026-08-09T10:00:00Z", "datetime")
    %w[2026-08-09t10:00:00Z 2026-08-09T10:00Z 2026-08-09T24:00:00Z 2026-08-09T23:59:60Z 2026-08-09T10:00:00.Z
       20260809T100000Z 2026-02-30T10:00:00Z].each { |text| assert_undefined(text, "datetime") }
  end

  # sabotage: drop the YEARS check in IsoText.in_years; the 9999 text
  # answers an instant in the year 10000 and its assert_undefined fails.
  def test_an_instant_outside_the_years_the_reference_holds_is_undefined
    assert_undefined("9999-12-31T23:00:00-05:00", "datetime")
    assert_undefined("-9999-01-01T00:00:00+01:00", "datetime")
    assert_equal "-0001-12-31T23:00:00Z", cast(cast("0000-01-01T00:00:00+01:00", "datetime"), "string")
    assert_equal date(-1, 12, 31), cast(cast("0000-01-01T00:00:00+01:00", "datetime"), "date")
  end
end
