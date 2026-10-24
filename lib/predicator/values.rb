# frozen_string_literal: true

require_relative "civil"

module Predicator
  # predicator's undefined: an absence, where no value was ever supplied. It
  # is a value of its own and never Ruby's nil, which is predicator's null (a
  # value that is present and empty); the two are distinct in the language.
  # There is exactly one instance, {Predicator::UNDEFINED}, compared by
  # identity. The class is private to the package; the instance is the
  # value a host holds.
  class Undefined
    # @return [String] how the one instance prints
    def inspect = "Predicator::UNDEFINED"
    alias to_s inspect

    # The one instance is its own copy, so identity survives a dup or clone.
    # @return [Undefined] self
    def dup = self

    # @return [Undefined] self
    def clone(**) = self

    private_class_method :new
  end

  # The one {Undefined} instance.
  UNDEFINED = Undefined.send(:new).freeze
  private_constant :Undefined

  # A civil date: a year, a month and a day on the proleptic Gregorian
  # calendar, with no time of day and no zone. It is an immutable value,
  # equal to and hashed like any other date with the same three parts.
  #
  # @!attribute [r] year
  #   @return [Integer] the year; any Integer, though the tagged encoding
  #     carries 0 to 9999 only
  # @!attribute [r] month
  #   @return [Integer] the month, 1 to 12
  # @!attribute [r] day
  #   @return [Integer] the day of the month, 1 to the month's length
  Date = Data.define(:year, :month, :day) do
    # @param year [Integer]
    # @param month [Integer]
    # @param day [Integer]
    # @raise [ArgumentError] unless the three parts name a calendar date
    def initialize(year:, month:, day:)
      unless Civil.civil?(year, month, day)
        raise ArgumentError, "#{[year, month, day].inspect} does not name a calendar date"
      end

      super
    end

    # The date as ISO 8601 text, `YYYY-MM-DD`, for a year from 0 to 9999.
    # Other years are written with as many digits as they take and a leading
    # minus sign below zero, which ISO 8601 leaves to agreement.
    #
    # @return [String]
    def to_s
      digits = format("%04d", year.abs)
      "#{"-" if year.negative?}#{digits}-#{format("%02d", month)}-#{format("%02d", day)}"
    end

    # @return [String]
    def inspect = "#<Predicator::Date #{self}>"
  end

  # An instant in UTC: a whole number of seconds since 1970-01-01T00:00:00Z
  # and a microsecond within that second, the sub-second precision the
  # reference's ISA states for an instant. It is an immutable value, equal to
  # and hashed like any other at the same instant.
  #
  # @!attribute [r] epoch_seconds
  #   @return [Integer] whole seconds since the epoch, negative before it
  # @!attribute [r] microsecond
  #   @return [Integer] the microsecond of that second, 0 to 999999
  DateTime = Data.define(:epoch_seconds, :microsecond) do
    # @param epoch_seconds [Integer]
    # @param microsecond [Integer] 0 to 999999
    # @raise [ArgumentError] when a part is not an Integer in its range
    def initialize(epoch_seconds:, microsecond: 0)
      unless epoch_seconds.is_a?(Integer) && Civil.within?(microsecond, 999_999)
        raise ArgumentError, "#{[epoch_seconds, microsecond].inspect} is not an instant"
      end

      super
    end

    # The instant as canonical ISO 8601 text in UTC: the fraction left out
    # when the microsecond is zero and exactly six digits when it is not
    # (the form the tagged encoding and the reference's string cast both
    # write).
    #
    # @return [String]
    def to_s
      fraction = microsecond.zero? ? "" : format(".%06d", microsecond)
      format("%<date>sT%<hour>02d:%<minute>02d:%<second>02d%<fraction>sZ",
             date: Civil.date_of(self), hour:, minute:, second:, fraction:)
    end

    # @return [String]
    def inspect = "#<Predicator::DateTime #{self}>"

    private

    # The hour of the day, 0 to 23, the minute and the second, in UTC.
    def hour = seconds_of_day / 3600
    def minute = (seconds_of_day % 3600) / 60
    def second = seconds_of_day % 60

    def seconds_of_day = epoch_seconds % Civil::SECONDS_PER_DAY
  end

  # A duration: the eight units the reference's duration carries, every one
  # present and defaulting to zero. The set never varies with the units an
  # expression named. It is an immutable value.
  #
  # @!attribute [r] years
  #   @return [Integer]
  # @!attribute [r] months
  #   @return [Integer]
  # @!attribute [r] weeks
  #   @return [Integer]
  # @!attribute [r] days
  #   @return [Integer]
  # @!attribute [r] hours
  #   @return [Integer]
  # @!attribute [r] minutes
  #   @return [Integer]
  # @!attribute [r] seconds
  #   @return [Integer]
  # @!attribute [r] milliseconds
  #   @return [Integer]
  Duration = Data.define(:years, :months, :weeks, :days, :hours, :minutes, :seconds, :milliseconds) do
    # Every unit given defaults to zero.
    #
    # @raise [ArgumentError] when a unit is not an Integer
    def initialize(years: 0, months: 0, weeks: 0, days: 0, hours: 0, minutes: 0, seconds: 0, milliseconds: 0)
      units = { years:, months:, weeks:, days:, hours:, minutes:, seconds:, milliseconds: }
      wrong = units.reject { |_, amount| amount.is_a?(Integer) }
      raise ArgumentError, "a duration's units are Integers: #{wrong.inspect}" unless wrong.empty?

      super(**units)
    end
  end
end
