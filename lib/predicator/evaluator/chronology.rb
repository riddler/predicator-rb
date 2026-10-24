# frozen_string_literal: true

module Predicator
  module Evaluator
    # The date arithmetic `add` and `subtract` reach for, as the reference
    # states it at the tag the corpus names (its ISA, docs/isa.md, section 5,
    # and its duration module where the ISA is silent).
    #
    # Two dates are apart by a duration in whole days and two datetimes by a
    # duration in whole seconds, truncated toward zero; a date beside a
    # datetime is read at midnight UTC. A date moved by a duration stays a
    # date and a datetime stays a datetime. A month counts as 30 days and a
    # year as 365, with no calendar rule and no month-end clamp: the
    # reference's own conversion, which it calls approximate.
    #
    # The module holds no state.
    module Chronology
      MICROS_PER_SECOND = 1_000_000

      # The day count of each date unit of a duration.
      DAYS = { weeks: 7, months: 30, years: 365 }.freeze

      # The second count of each time unit of a duration.
      SECONDS = { minutes: 60, hours: 3600 }.freeze

      module_function

      # Whether value is a date or a datetime.
      def chronological?(value) = value.is_a?(Predicator::Date) || value.is_a?(Predicator::DateTime)

      # left minus right, both dates or datetimes, as a duration.
      def difference(left, right)
        if left.is_a?(Predicator::Date) && right.is_a?(Predicator::Date)
          return Duration.new(days: Civil.days_of(left) - Civil.days_of(right))
        end

        Duration.new(seconds: truncated_seconds(micros(left) - micros(right)))
      end

      # anchor (a date or a datetime) moved by duration, forward when sign is
      # 1 and back when it is -1.
      def shift(anchor, duration, sign)
        if anchor.is_a?(Predicator::Date)
          return Civil.date_of_days(Civil.days_of(anchor) + (sign * whole_days(duration)))
        end

        moved = micros(anchor) + (sign * datetime_step(duration))
        Predicator::DateTime.new(epoch_seconds: moved.div(MICROS_PER_SECOND), microsecond: moved % MICROS_PER_SECOND)
      end

      # The days a date moves by: the date units, then the whole days the
      # time units add up to, truncated toward zero. Milliseconds do not move
      # a date.
      def whole_days(duration)
        time = duration.seconds + SECONDS.sum { |unit, seconds| duration.public_send(unit) * seconds }
        date_days(duration) + truncated(time, Civil::SECONDS_PER_DAY)
      end

      # The microseconds a datetime moves by. A positive milliseconds moves it
      # by milliseconds; any other duration moves it by whole seconds, its
      # milliseconds left out, as the reference splits the two.
      def datetime_step(duration)
        seconds = duration.seconds + SECONDS.sum { |unit, factor| duration.public_send(unit) * factor } +
                  (date_days(duration) * Civil::SECONDS_PER_DAY)
        step = seconds * MICROS_PER_SECOND
        duration.milliseconds.positive? ? step + (duration.milliseconds * 1000) : step
      end

      def date_days(duration) = duration.days + DAYS.sum { |unit, days| duration.public_send(unit) * days }

      # A date at midnight UTC, or a datetime, as microseconds since the epoch.
      def micros(value)
        return Civil.days_of(value) * Civil::SECONDS_PER_DAY * MICROS_PER_SECOND if value.is_a?(Predicator::Date)

        (value.epoch_seconds * MICROS_PER_SECOND) + value.microsecond
      end

      def truncated_seconds(micros) = truncated(micros, MICROS_PER_SECOND)

      # amount divided by unit, truncated toward zero.
      def truncated(amount, unit)
        whole = amount.abs / unit
        amount.negative? ? -whole : whole
      end
    end
    private_constant :Chronology
  end
end
