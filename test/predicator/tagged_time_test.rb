# frozen_string_literal: true

require_relative "tagged_helper"

# The codec over the three tags that carry time: date, datetime, duration.
class TaggedTimeTest < Minitest::Test
  include TaggedHelper

  # sabotage: loosen DATE_TEXT's month and day to \d{1,2} in Reader; the
  # assert_equal on the refusal of "2026-8-6" fails.
  def test_the_date_tag
    assert_equal DATE, decoded('{"$type":"date","value":"2026-08-06"}')
    assert_equal '{"$type":"date","value":"2026-08-06"}', Tagged.encode!(DATE)
    assert_equal '{"$type":"date","value":"0000-01-01"}', Tagged.encode!(Predicator::Date.new(0, 1, 1))
    assert_equal '{"$type":"date","value":"9999-12-31"}', Tagged.encode!(Predicator::Date.new(9999, 12, 31))
    ['"2026-02-30"', '"2026-8-6"', '"20260806"', "20260806", '"2026-08-06T00:00:00Z"'].each do |body|
      assert_equal "invalid_tagged_value", refusal(Tagged.decode(%({"$type":"date","value":#{body}}))), body
    end
  end

  # sabotage: answer value.to_s unchecked from Writer.carried; year 10000 is
  # written and the assert_equal on its refusal fails.
  def test_a_date_or_instant_outside_four_digit_years_is_not_encoded
    far = Predicator::Date.new(10_000, 1, 1)
    before = CIVIL.instant_at(Predicator::Date.new(-1, 1, 1))

    assert_equal(%w[invalid_tagged_value invalid_tagged_value], [far, before].map { |v| refusal(Tagged.encode(v)) })
  end

  # sabotage: drop the microsecond: argument from Reader.local_instant's
  # Civil.instant_at call; the assert_equal on the half second fails.
  def test_the_datetime_tag_writes_no_fraction_or_six_digits
    noon = CIVIL.instant_at(DATE, 12)
    half = CIVIL.instant_at(DATE, 12, microsecond: 500_000)

    assert_equal noon, decoded('{"$type":"datetime","value":"2026-08-06T12:00:00Z"}')
    assert_equal half, decoded('{"$type":"datetime","value":"2026-08-06T12:00:00.500000Z"}')
    assert_equal '{"$type":"datetime","value":"2026-08-06T12:00:00Z"}', Tagged.encode!(noon)
    assert_equal '{"$type":"datetime","value":"2026-08-06T12:00:00.500000Z"}', Tagged.encode!(half)
  end

  # sabotage: take "#{fraction}000000"[0, 3] in Reader.local_instant; the
  # assert_equal on the microseconds read (the one-digit fraction's first)
  # fails.
  def test_a_datetime_fraction_of_any_length_reads_to_microseconds
    fractions = %w[.5 .123456789 .000 .000001].map do |fraction|
      decoded(%({"$type":"datetime","value":"2026-08-06T12:00:00#{fraction}Z"})).microsecond
    end

    assert_equal [500_000, 123_456, 0, 1], fractions
  end

  # sabotage: add the offset rather than subtract it in
  # Reader.read_datetime; the assert_equal on "+01:00" fails.
  def test_a_datetime_with_an_offset_reads_as_the_instant_it_names
    eleven = CIVIL.instant_at(DATE, 11)

    %w[2026-08-06T12:00:00+01:00 2026-08-06T10:30:00-0030 2026-08-06T12:00:00+01
       2026-08-06T11:00:00+00:00].each do |text|
      assert_equal eleven, decoded(%({"$type":"datetime","value":"#{text}"})), text
    end
    assert_equal eleven, decoded('{"$type":"datetime","value":"2026-08-06 11:00:00Z"}')
  end

  # sabotage: drop `return if zone == "-00:00"` from Reader.read_offset; the
  # assert_equal on "-00:00" fails.
  def test_a_datetime_that_names_no_instant_is_refused
    %w[2026-08-06T12:00:00-00:00 2026-08-06T24:00:00Z 2026-08-06T12:60:00Z 2026-08-06T12:00:60Z 2026-02-30T12:00:00Z
       2026-08-06T12:00:00 2026-08-06T12:00:00+24:00 2026-08-06T12:00:00+01:60 2026-08-06t12:00:00Z
       0000-01-01T00:00:00+01:00 9999-12-31T23:59:59-01:00].each do |text|
      assert_equal "invalid_tagged_value", refusal(Tagged.decode(%({"$type":"datetime","value":"#{text}"}))), text
    end
  end

  # sabotage: add `return if sign == "-" && seconds.zero?` before the last
  # line of Reader.read_offset; "-0000" is refused and the assert_equal on
  # the instants read fails.
  def test_a_negative_zero_offset_other_than_minus_00_00_reads_as_utc
    noon = CIVIL.instant_at(DATE, 12)
    read = %w[-0000 -00 +0000 +00].map do |zone|
      Tagged.decode(%({"$type":"datetime","value":"2026-08-06T12:00:00#{zone}"})).value
    end

    assert_equal [noon] * 4, read
  end

  # sabotage: narrow the fraction's mark to `\.` in Reader's DATETIME_TEXT;
  # the comma fractions are refused and the assert_equal on the microseconds
  # read fails.
  def test_a_datetime_fraction_may_follow_a_comma
    read = %w[,5 ,123456789].map do |fraction|
      Tagged.decode(%({"$type":"datetime","value":"2026-08-06T12:00:00#{fraction}Z"})).value&.microsecond
    end

    assert_equal [500_000, 123_456], read
    assert_equal "invalid_tagged_value", refusal(Tagged.decode('{"$type":"datetime","value":"2026-08-06T12:00:00,Z"}'))
  end

  # sabotage: write milliseconds whatever its value in Writer.duration; the
  # assert_equal on the compact text fails.
  def test_the_duration_tag_writes_milliseconds_only_when_it_is_not_zero
    three = Predicator::Duration.new(days: 3)
    with_ms = Predicator::Duration.new(milliseconds: 500)

    assert_equal three, decoded(%({"$type":"duration","value":#{THREE_DAYS}}))
    assert_equal %({"$type":"duration","value":#{THREE_DAYS}}), Tagged.encode!(three)
    assert_equal with_ms, decoded(Tagged.encode!(with_ms))
    assert_match(/"seconds":0,"milliseconds":500\}\}\z/, Tagged.encode!(with_ms))
  end

  # sabotage: drop the missing-unit test from Reader.read_duration; the
  # body without years decodes and the assert_equal fails.
  def test_a_duration_body_that_is_not_the_unit_map_is_refused
    bodies = [THREE_DAYS.sub('"years":0,', ""), THREE_DAYS.sub("}", ',"fortnights":1}'),
              THREE_DAYS.sub('"days":3', '"days":1.5'), "[]", '"P3D"']
    bodies.each do |body|
      assert_equal "invalid_tagged_value", refusal(Tagged.decode(%({"$type":"duration","value":#{body}}))), body
    end
  end
end
