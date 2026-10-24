# frozen_string_literal: true

module Predicator
  # Calendar arithmetic on the proleptic Gregorian calendar, written by hand so
  # that the package needs no date library: a civil date (year, month, day) to
  # a count of days since 1970-01-01 and back, and the tests built on them.
  #
  # Every function takes and answers Integers. The algorithms are the
  # era-based ones published by Howard Hinnant ("chrono-Compatible Low-Level
  # Date Algorithms"), exact for every Integer year, so a year before 1 or
  # after 9999 converts as well as any other.
  #
  # The module holds no state. It is private to the package: the value classes
  # in values.rb and the codec in tagged.rb are its callers.
  module Civil
    # Seconds in a civil day; an instant's day is its epoch second divided by
    # this, rounded toward the past.
    SECONDS_PER_DAY = 86_400

    # The days in each month of a year that is not a leap year.
    MONTH_LENGTHS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31].freeze

    module_function

    # The count of days from 1970-01-01 to the civil date year-month-day,
    # negative before it. month and day are taken as given; a caller wanting
    # to know they name a date asks civil?.
    def days_from_civil(year, month, day)
      shifted = month <= 2 ? year - 1 : year
      era = shifted.div(400)
      (era * 146_097) + day_of_era(shifted - (era * 400), day_of_year(month, day)) - 719_468
    end

    # The civil date days after 1970-01-01, as [year, month, day].
    def civil_from_days(days)
      shifted = days + 719_468
      era = shifted.div(146_097)
      era_day = shifted - (era * 146_097)
      era_year = year_of_era(era_day)
      month, day = month_and_day(era_day - day_of_era(era_year, 0))
      [era_year + (era * 400) + (month <= 2 ? 1 : 0), month, day]
    end

    # The day of a year that starts on March 1st.
    def day_of_year(month, day) = (((153 * (month + (month > 2 ? -3 : 9))) + 2) / 5) + day - 1

    # The day of a 400-year era, from the year of the era and the day of
    # that (March-based) year.
    def day_of_era(year_of_era, day_of_year)
      (year_of_era * 365) + (year_of_era / 4) - (year_of_era / 100) + day_of_year
    end

    # The year of a 400-year era a day of the era falls in.
    def year_of_era(day_of_era)
      (day_of_era - (day_of_era / 1460) + (day_of_era / 36_524) - (day_of_era / 146_096)) / 365
    end

    # The civil month and day of a day of a March-based year.
    def month_and_day(day_of_year)
      month_from_march = ((5 * day_of_year) + 2) / 153
      day = day_of_year - (((153 * month_from_march) + 2) / 5) + 1
      [month_from_march + (month_from_march < 10 ? 3 : -9), day]
    end

    # Whether part is an Integer from 0 to top.
    def within?(part, top) = part.is_a?(Integer) && part.between?(0, top)

    # Whether year, month and day are Integers naming a date on the calendar:
    # a month from 1 to 12 and a day that month has in that year. It reads
    # the month lengths and the leap-year rule, not the day count, so the two
    # conversions above are checked against it rather than by it.
    def civil?(year, month, day)
      return false unless [year, month, day].all?(Integer) && month.between?(1, 12)

      day.between?(1, days_in_month(year, month))
    end

    # The days in a month of a year.
    def days_in_month(year, month)
      return 29 if month == 2 && leap?(year)

      MONTH_LENGTHS[month - 1]
    end

    # Whether a year is a leap year on the proleptic Gregorian calendar.
    def leap?(year) = (year % 4).zero? && (!(year % 100).zero? || (year % 400).zero?)
  end
  private_constant :Civil
end
