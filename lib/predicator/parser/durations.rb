# frozen_string_literal: true

module Predicator
  module Parser
    # Duration literals and the words that make one a relative date, read
    # into the parse that includes this module.
    #
    # The lexer writes `3d8h` as a number and a unit per component. A literal
    # written in whole numbers keeps its components as written, a unit
    # written twice included. A component written with a point is expanded
    # as the reference expands it: the whole part keeps its unit when it is
    # not zero, and the fraction's worth, which must be a whole number of
    # milliseconds (a month 30 days, a year 365), is spent largest first
    # through days, hours, minutes, seconds and milliseconds, the pair
    # `[0, unit]` standing for a component worth nothing. An inexact
    # fraction is refused over its component; a unit named twice after an
    # expansion is refused over the whole literal, the alphabetically first
    # such unit named.
    module Durations
      # Each unit's suffix and its worth in milliseconds.
      MILLISECONDS = DurationText::UNITS.values.to_h.freeze

      # The units a fraction's worth is spent into, largest first.
      LADDER = %w[d h m s ms].freeze

      private

      # The duration (or relative date) a number starts, when a unit follows
      # it; nil when none does, and nothing is consumed.
      def duration_from(first, start)
        return unless at?(:duration_unit)

        unit = advance
        components = [[first, unit.value, between(start, end_of(unit))]]
        components << component while component_follows?
        units = whole_units(components)
        direction(Ast::Duration.new(units:, position: start, span: between(start, end_of(previous))))
      end

      def component_follows?
        %i[integer fractional_number].include?(peek.type) && @tokens[@index + 1].type == :duration_unit
      end

      def component
        number = advance
        unit = advance
        [number.value, unit.value, between(start_of(number), end_of(unit))]
      end

      def whole_units(components)
        written = components.map { |value, unit, _| [value, unit] }
        return written if written.none? { |value, _| fraction?(value) }

        units = components.flat_map { |parts| expanded(*parts) }
        twice = repeated(units)
        twice ? unit_twice(twice, components) : units
      end

      # The alphabetically first unit named more than once, if one is.
      def repeated(units) = units.map(&:last).tally.select { |_, count| count > 1 }.keys.min

      def unit_twice(unit, components)
        refuse("duration_unit_twice", "Duration literal names the '#{unit}' unit twice after expanding a fraction",
               nil, between(components.first.last.start, components.last.last.end))
      end

      def fraction?(value) = value.is_a?(Lexer::Fraction)

      def expanded(value, unit, span)
        return [[value, unit]] unless fraction?(value)

        pairs = fraction_units(value, unit)
        return pairs if pairs

        refuse("duration_fraction", "Duration fraction is not a whole number of milliseconds: " \
                                    "#{value.whole}.#{value.fraction}#{unit}", nil, span)
      end

      # The whole-unit pairs one component with a point is worth, or nil
      # when its fraction is not a whole number of milliseconds.
      def fraction_units(value, unit)
        remainder, inexact = (Integer(value.fraction, 10) * MILLISECONDS.fetch(unit)).divmod(10**value.fraction.size)
        return unless inexact.zero?

        pairs = (value.whole.positive? ? [[value.whole, unit]] : []) + spent(remainder)
        pairs.empty? ? [[0, unit]] : pairs
      end

      def spent(milliseconds)
        LADDER.filter_map do |suffix|
          amount, milliseconds = milliseconds.divmod(MILLISECONDS.fetch(suffix))
          [amount, suffix] if amount.positive?
        end
      end

      # `ago`, or `from now`, after a duration; the node is at the word.
      def direction(duration)
        return duration unless %i[ago_op from_op].include?(peek.type)

        word = advance
        last = word.type == :ago_op ? word : expect(:now_op, "expected_now", "Expected 'now' after 'from' but found")
        Ast::RelativeDate.new(duration:, direction: word.type == :ago_op ? :ago : :future, position: start_of(word),
                              span: reaching(duration, last))
      end
    end
    private_constant :Durations
  end
end
