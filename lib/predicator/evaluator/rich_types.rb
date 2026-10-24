# frozen_string_literal: true

module Predicator
  module Evaluator
    # The rich-type opcodes, as the reference's ISA (docs/isa.md, section 5)
    # states them: the handlers {Machine} runs for `duration`,
    # `relative_date`, `object_new` and `object_set`.
    #
    # `relative_date` is the one opcode here whose answer depends on the
    # time. It reads the clock the caller passed to the evaluation, through
    # `now`, which reads that clock at most once per evaluation.
    #
    # Two refusals are narrower than the reference's, which tests its own
    # host map type in both places: `relative_date` takes a duration alone
    # (the reference also takes any map, reading each unit it lacks as zero),
    # and `object_set` writes into a map alone (the reference also writes
    # into a duration, a date or a datetime, each a map there). Each refused
    # value is answered with the reason the ISA names for a non-map.
    module RichTypes
      # Every unit spelling `duration` accepts, and the unit each names.
      DURATION_UNITS = {
        years: %w[y year years], months: %w[mo month months], weeks: %w[w week weeks],
        days: %w[d day days], hours: %w[h hour hours], minutes: %w[m min minute minutes],
        seconds: %w[s sec second seconds], milliseconds: %w[ms millisecond milliseconds]
      }.flat_map { |unit, spellings| spellings.map { |spelling| [spelling, unit] } }.to_h.freeze

      # Which way each direction `relative_date` accepts moves the time.
      DIRECTIONS = { "ago" => -1, "last" => -1, "future" => 1, "next" => 1 }.freeze

      private

      # Pushes the duration the unit pairs name, every unit they do not name
      # at zero. A later pair naming a unit overwrites an earlier one. A pair
      # that is not an Integer and a String is refused before its unit is
      # read, and pairs are read in order, so the first bad pair decides.
      def duration(at, pairs)
        units = {}
        pairs.each do |pair|
          return invalid_duration("invalid_duration_format", "is not [integer, unit]", pair) unless unit_pair?(pair)

          unit = DURATION_UNITS[pair.last]
          return invalid_duration("invalid_duration_unit", "names no unit", pair) unless unit

          units[unit] = pair.first
        end
        push(at, Duration.new(**units))
      end

      def unit_pair?(pair) = pair.is_a?(Array) && pair.size == 2 && pair.first.is_a?(Integer) && pair.last.is_a?(String)

      def invalid_duration(reason, says, pair)
        EvaluationError.new(reason:, message: "duration pair #{pair.inspect} #{says}")
      end

      # Pops a duration and pushes the evaluation's current time moved by it:
      # back for "ago" and "last", forward for "future" and "next". The stack
      # depth is checked first, then the popped value, then the direction.
      def relative_date(at, direction)
        return insufficient("relative_date") if @stack.empty?

        moved = @stack.pop
        return invalid_stack_value("relative_date", "a duration") unless moved.is_a?(Duration)

        sign = DIRECTIONS[direction]
        unless sign
          return EvaluationError.new(reason: "invalid_direction",
                                     message: "relative_date does not accept #{direction.inspect}")
        end

        push(at, Chronology.shift(now, moved, sign))
      end

      # The current time of this evaluation: the clock's answer the first
      # time it is asked for, and the same instant every time after.
      def now
        return @now if @now

        instant = @clock.call
        unless instant.is_a?(Predicator::DateTime)
          raise ArgumentError, "the clock answered #{instant.inspect}, not a Predicator::DateTime"
        end

        @now = instant
      end

      def object_new(at) = push(at, {})

      # Pops the value, then the map beneath it, and pushes a copy of that
      # map with key set to the value. The map popped is not changed: it may
      # be one the context holds. The depth is checked before the map.
      def object_set(at, key)
        return insufficient("object_set") if @stack.size < 2

        value = @stack.pop
        target = @stack.pop
        return invalid_stack_value("object_set", "a map beneath the value") unless target.is_a?(Hash)

        push(at, target.merge(key => value))
      end

      def invalid_stack_value(opcode, wanted)
        EvaluationError.new(reason: "invalid_stack_value", message: "#{opcode} expects #{wanted}")
      end
    end
    private_constant :RichTypes
  end
end
