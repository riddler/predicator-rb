# frozen_string_literal: true

module Predicator
  # ISO 8601 text read as the `::date` and `::datetime` casts read it: the
  # forms the reference's host parser accepts, which the reference hands such
  # text to.
  #
  # A date is four digits of year, optionally signed (the sign the year's),
  # a month and a day, naming a real calendar date. A datetime is such a
  # date, `T` or a space, hours, minutes and seconds of a time a day has, an
  # optional fraction after a full stop or a comma (read to the microsecond,
  # further digits dropped), and an offset: `Z`, or a sign with two digits of
  # hours and optionally two of minutes, with or without a colon, of at most
  # 23 hours and 59 minutes. The text `-00:00` is refused, as the reference
  # refuses it, while `-0000` and `-00` read as UTC. The offset is applied:
  # the answer is the instant the text names, in UTC, and an instant whose
  # year in UTC falls outside {YEARS} is refused (the reference raises
  # there).
  #
  # Each field of the offset is two digits. The reference's ISA (docs/isa.md,
  # section 5) asks `::datetime` for an ISO 8601 datetime with a UTC offset,
  # and an ISO 8601 offset's hour and minute fields are digits with no sign
  # of their own, so a text such as `+-5:30` is refused here. The
  # reference's host parser reads each field as an integer that may carry a
  # sign and answers an instant for it.
  #
  # The module holds no state. It is private to the package.
  module IsoText
    DATE_TEXT = /\A([+-]?)([0-9]{4})-([0-9]{2})-([0-9]{2})\z/
    DATETIME_TEXT = /\A([+-]?)([0-9]{4})-([0-9]{2})-([0-9]{2})[T ]([0-9]{2}):([0-9]{2}):([0-9]{2})
                     (?:[.,]([0-9]+))?(Z|[+-][0-9]{2}(?::?[0-9]{2})?)\z/x
    OFFSET_TEXT = /\A([+-])([0-9]{2}):?([0-9]{2})?\z/

    # The years an instant may fall in, in UTC.
    YEARS = (-9999..9999)

    module_function

    # @param text [String]
    # @return [Date, nil] the date the text names, or nil
    def read_date(text)
      match = DATE_TEXT.match(text)
      civil_date(*match.captures) if match
    end

    # @param text [String]
    # @return [DateTime, nil] the instant the text names, or nil
    def read_datetime(text)
      instant = read_instant(text)
      in_years(instant) if instant
    end

    # The instant the text names, whatever its year in UTC: a datetime
    # literal in source reads its text so, as the reference's literal does.
    #
    # @param text [String]
    # @return [DateTime, nil] the instant the text names, or nil
    def read_instant(text)
      match = DATETIME_TEXT.match(text)
      return unless match

      sign, year, month, day, *clock, fraction, zone = match.captures
      local = local_instant(civil_date(sign, year, month, day), clock.map { |part| Integer(part, 10) }, fraction)
      offset = read_offset(zone)
      local.with(epoch_seconds: local.epoch_seconds - offset) if local && offset
    end

    def civil_date(sign, *parts)
      year, month, day = parts.map { |part| Integer(part, 10) }
      year = -year if sign == "-"
      Date.new(year:, month:, day:) if Civil.civil?(year, month, day)
    end

    def local_instant(date, (hour, minute, second), fraction)
      return unless date && hour <= 23 && minute <= 59 && second <= 59

      microsecond = Integer("#{fraction}000000"[0, 6], 10)
      DateTime.at(date, hour, minute, second, microsecond:)
    end

    def in_years(instant) = (instant if YEARS.cover?(instant.to_date.year))

    # The seconds the offset stands east of UTC, or nil when the reference
    # refuses it.
    def read_offset(zone)
      return 0 if zone == "Z"
      return if zone == "-00:00"

      sign, hours, minutes = OFFSET_TEXT.match(zone).captures
      hours = Integer(hours, 10)
      minutes = Integer(minutes || "0", 10)
      return if hours > 23 || minutes > 59

      seconds = (hours * 3600) + (minutes * 60)
      sign == "-" ? -seconds : seconds
    end
  end
  private_constant :IsoText
end
