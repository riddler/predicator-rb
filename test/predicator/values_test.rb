# frozen_string_literal: true

require "test_helper"

# The value classes the domain adds to Ruby's own values: the one undefined,
# civil dates, instants and durations.
class ValuesTest < Minitest::Test
  # sabotage: make Undefined#dup answer super; the assert_same on the dup
  # fails.
  def test_undefined_is_one_value_distinct_from_nil
    assert_same Predicator::UNDEFINED, Predicator::UNDEFINED.dup
    assert_same Predicator::UNDEFINED, Predicator::UNDEFINED.clone
    refute_nil Predicator::UNDEFINED
    assert_raises(NoMethodError) { Predicator::Undefined.new }
    assert_equal "Predicator::UNDEFINED", Predicator::UNDEFINED.inspect
    assert_predicate Predicator::UNDEFINED, :frozen?
  end

  # sabotage: drop the `- 719_468` from Civil.days_from_civil; the
  # assert_equal on the epoch's day count fails.
  def test_a_date_converts_to_and_from_its_day_count
    assert_equal 0, Predicator::Date.new(1970, 1, 1).to_days
    assert_equal 20_671, Predicator::Date.new(2026, 8, 6).to_days
    assert_equal(-1, Predicator::Date.new(1969, 12, 31).to_days)
    assert_equal Predicator::Date.new(2000, 2, 29), Predicator::Date.from_days(11_016)
  end

  # sabotage: replace shifted.div(400) with (shifted / 400.0).to_i in
  # Civil.days_from_civil (truncating toward zero); the round trip of a
  # date before year 0 fails.
  def test_the_day_count_round_trips_across_eras
    [[-1, 3, 1], [0, 2, 29], [1, 1, 1], [1600, 2, 29], [1900, 3, 1], [9999, 12, 31], [12_345, 6, 7]].each do |parts|
      date = Predicator::Date.new(*parts)

      assert_equal date, Predicator::Date.from_days(date.to_days)
    end
  end

  # sabotage: replace the day test in Civil.civil? with true; the
  # assert_raises on February 29th of 1900 fails.
  def test_a_date_must_name_a_calendar_date
    [[1900, 2, 29], [2026, 2, 29], [2026, 0, 1], [2026, 13, 1], [2026, 4, 31], [2026, 1, 0],
     [2026, "1", 1]].each do |parts|
      assert_raises(ArgumentError, parts.inspect) { Predicator::Date.new(*parts) }
    end
    assert_raises(ArgumentError) { Predicator::Date.from_days(1.5) }
    assert_equal [29, 29], [Predicator::Date.new(2000, 2, 29).day, Predicator::Date.new(2024, 2, 29).day]
  end

  # sabotage: format the year with %d rather than %04d in Date#to_s; the
  # assert_equal on year 5 fails.
  def test_a_date_writes_iso_text
    assert_equal "2026-08-06", Predicator::Date.new(2026, 8, 6).to_s
    assert_equal "0005-01-02", Predicator::Date.new(5, 1, 2).to_s
    assert_equal "-0001-03-01", Predicator::Date.new(-1, 3, 1).to_s
    assert_equal "#<Predicator::Date 2026-08-06>", Predicator::Date.new(2026, 8, 6).inspect
  end

  # sabotage: define `def hash = object_id` in Date; the assert_equal on
  # the hash lookup fails.
  def test_dates_are_equal_and_hash_by_value
    one = Predicator::Date.new(2026, 8, 6)
    other = Predicator::Date.new(year: 2026, month: 8, day: 6)

    assert_equal one, other
    assert_equal 1, { one => 1 }[other]
  end

  # sabotage: drop `+ (minute * 60)` from DateTime.at; the assert_equal on
  # the epoch seconds fails.
  def test_a_datetime_is_built_from_a_date_and_a_time_of_day
    instant = Predicator::DateTime.at(Predicator::Date.new(2026, 8, 6), 12, 30, 15, microsecond: 500_000)

    assert_equal 1_786_019_415, instant.epoch_seconds
    assert_equal [12, 30, 15, 500_000], [instant.hour, instant.minute, instant.second, instant.microsecond]
    assert_equal Predicator::Date.new(2026, 8, 6), instant.to_date
  end

  # sabotage: truncate toward zero, epoch_seconds.fdiv(86_400).to_i, in
  # DateTime#to_date; for an instant before the epoch the date is a day late
  # and the assert_equal fails.
  def test_an_instant_before_the_epoch_reads_its_civil_parts_toward_the_past
    instant = Predicator::DateTime.new(epoch_seconds: -1)

    assert_equal Predicator::Date.new(1969, 12, 31), instant.to_date
    assert_equal [23, 59, 59], [instant.hour, instant.minute, instant.second]
  end

  # sabotage: write the fraction with %d rather than %06d in DateTime#to_s;
  # the assert_equal on a five-microsecond fraction fails.
  def test_a_datetime_writes_canonical_text
    date = Predicator::Date.new(2026, 8, 6)

    assert_equal "2026-08-06T12:00:00Z", Predicator::DateTime.at(date, 12).to_s
    assert_equal "2026-08-06T12:00:00.000005Z", Predicator::DateTime.at(date, 12, microsecond: 5).to_s
    assert_equal "#<Predicator::DateTime 2026-08-06T12:00:00.500000Z>",
                 Predicator::DateTime.at(date, 12, microsecond: 500_000).inspect
  end

  # sabotage: define `def hash = object_id` in DateTime; the assert_equal on
  # the hash lookup fails.
  def test_datetimes_are_equal_and_hash_by_instant
    one = Predicator::DateTime.at(Predicator::Date.new(2026, 8, 6), 12, microsecond: 5)
    other = Predicator::DateTime.new(epoch_seconds: one.epoch_seconds, microsecond: 5)

    assert_equal one, other
    assert_equal 1, { one => 1 }[other]
    refute_equal one, Predicator::DateTime.new(epoch_seconds: one.epoch_seconds)
  end

  # sabotage: drop the microsecond range test from DateTime#initialize; the
  # assert_raises on a million microseconds fails.
  def test_a_datetime_refuses_parts_out_of_range
    date = Predicator::Date.new(2026, 8, 6)

    [[0, 1_000_000], [0.5, 0], [0, -1], [0, 0.5]].each do |seconds, microsecond|
      assert_raises(ArgumentError, [seconds, microsecond].inspect) do
        Predicator::DateTime.new(epoch_seconds: seconds, microsecond:)
      end
    end
    [[date, -1], [date, 24], [date, 0, 60], ["2026-08-06"]].each do |parts|
      assert_raises(ArgumentError, parts.inspect) { Predicator::DateTime.at(*parts) }
    end
  end

  # sabotage: default milliseconds to 1 in Duration#initialize; the
  # assert_equal on the eight zeroes fails.
  def test_a_duration_carries_all_eight_units_defaulting_to_zero
    duration = Predicator::Duration.new(days: 3)

    assert_equal({ years: 0, months: 0, weeks: 0, days: 3, hours: 0, minutes: 0, seconds: 0, milliseconds: 0 },
                 duration.to_h)
    assert_equal duration, Predicator::Duration.new(days: 3, milliseconds: 0)
    assert_equal 1, { duration => 1 }[Predicator::Duration.new(days: 3)]
  end

  # sabotage: make Duration#initialize skip the Integer test; the
  # assert_raises on a Float unit fails.
  def test_a_duration_refuses_a_unit_that_is_not_an_integer
    assert_raises(ArgumentError) { Predicator::Duration.new(hours: 1.5) }
    assert_raises(ArgumentError) { Predicator::Duration.new(days: nil) }
  end
end
