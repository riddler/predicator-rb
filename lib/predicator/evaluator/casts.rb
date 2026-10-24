# frozen_string_literal: true

module Predicator
  module Evaluator
    # The `cast` opcode, as the reference's ISA (docs/isa.md, section 5)
    # states it: the handler {Machine} runs for `cast`, and the conversion
    # matrix it reads through.
    #
    # The operand is one of the seven scalar type names in {TYPE_NAMES}; any
    # other operand is an unknown instruction. The cast pops one value and
    # pushes what that value is as the named type. It never fails but on an
    # empty stack: undefined converts to undefined, a value already of the
    # type passes through, and a conversion that cannot produce a value of
    # the type answers undefined (null, a list and a map included).
    #
    # The conversions:
    #
    # - integer: a float truncates toward zero; the text of an integer (an
    #   optional minus and decimal digits, nothing else) parses.
    # - float: an integer widens; the text of a number (an optional minus,
    #   digits and an optional fraction, no exponent) parses.
    # - string: an integer in decimal, a float as {FloatText} writes it, a
    #   boolean as `true` or `false`, a date as `YYYY-MM-DD`, a datetime in
    #   UTC as {Predicator::DateTime#to_s} writes it, a duration in the
    #   literal grammar {DurationText} writes.
    # - boolean: exactly the text `true` or `false`.
    # - date: a datetime's calendar date in UTC; the text of an ISO 8601
    #   calendar date that names a real date.
    # - datetime: a date at midnight UTC; the text of an ISO 8601 datetime
    #   carrying a UTC offset, as the instant it names.
    # - duration: the text of a duration literal, read as {DurationText}
    #   reads it.
    #
    # A map carrying the seven units the reference's duration always holds
    # (years to seconds), each an Integer, casts as a duration: it passes
    # through `::duration` and is written by `::string` in the literal
    # grammar. The map is read by its String unit names, as `relative_date`
    # reads one. `object_set` on a duration answers the map of its units
    # with the key written; when that key is not a unit name, the cast
    # writes the duration's own units, as the reference's cast does after
    # its `object_set`. When the key is a unit name the two part: this reads
    # the unit written (`days` set to 5 on `3d` writes `5d`, `milliseconds`
    # set to 500 writes `3d500ms`, a unit set to a non-Integer is
    # undefined), while the reference keeps its duration's own unit (`3d`),
    # since its durations carry their units under keys a written String key
    # does not replace. A String-keyed map from the context that carries
    # the unit names is a duration here and undefined in the reference. A
    # map whose units are not all Integers casts to undefined.
    #
    # The text forms `::date` and `::datetime` read are the reference's, as
    # {IsoText} states them.
    #
    # Where the reference raises rather than answering, this answers
    # undefined: an integer or a number's text too large for a finite Float
    # (the domain holds no other) and an instant {IsoText} refuses for its
    # year. A number's text too close to zero for any other Float reads as
    # zero, signed as the text is, as the reference reads it.
    module Casts
      # The type names a cast converts to.
      TYPE_NAMES = %w[integer float string boolean date datetime duration].freeze

      # The units a map carries to be read as a duration.
      DURATION_KEYS = %w[years months weeks days hours minutes seconds].freeze

      INTEGER_TEXT = /\A-?[0-9]+\z/
      FLOAT_TEXT = /\A-?[0-9]+(?:\.[0-9]+)?\z/

      # The magnitude from which a number rounds to no finite Float: halfway
      # between the largest Float and 2**1024.
      FLOAT_CEILING = (2**1024) - (2**970)

      # The magnitude at or below which a number rounds to a zero Float: half
      # the smallest Float above zero.
      FLOAT_FLOOR = Rational(1, 2**1075)

      # The method that converts to each type.
      CONVERTERS = TYPE_NAMES.to_h { |name| [name, :"cast_to_#{name}"] }.freeze

      private

      def cast(at, type_name)
        return insufficient("cast") if @stack.empty?

        value = @stack.pop
        push(at, UNDEFINED.equal?(value) ? UNDEFINED : send(CONVERTERS.fetch(type_name), value))
      end

      def cast_to_integer(value)
        case value
        when Integer then value
        when Float then value.truncate
        when String then INTEGER_TEXT.match?(value) ? Integer(value, 10) : UNDEFINED
        else UNDEFINED
        end
      end

      def cast_to_float(value)
        case value
        when Float then value
        when Integer then value.abs < FLOAT_CEILING ? value.to_f : UNDEFINED
        when String then FLOAT_TEXT.match?(value) ? float_of_text(value) : UNDEFINED
        else UNDEFINED
        end
      end

      # The Float nearest the number the text writes, or undefined when it is
      # too large for one. The magnitude is judged on the exact number first,
      # so the host parser is never asked for a Float out of its range.
      def float_of_text(text)
        magnitude = Rational(text).abs
        return UNDEFINED if magnitude >= FLOAT_CEILING
        return Float(text.start_with?("-") ? "-0" : "0") if magnitude <= FLOAT_FLOOR

        Float(text)
      end

      def cast_to_string(value)
        case value
        when String then value
        when Float then FloatText.spell(value)
        when Integer, true, false, Predicator::Date, Predicator::DateTime then value.to_s
        else cast_duration_text(value)
        end
      end

      def cast_duration_text(value)
        duration = cast_duration(value)
        duration ? DurationText.write(duration) : UNDEFINED
      end

      def cast_to_boolean(value)
        case value
        when true, false then value
        when "true" then true
        when "false" then false
        else UNDEFINED
        end
      end

      def cast_to_date(value)
        case value
        when Predicator::Date then value
        when Predicator::DateTime then value.to_date
        when String then IsoText.read_date(value) || UNDEFINED
        else UNDEFINED
        end
      end

      def cast_to_datetime(value)
        case value
        when Predicator::DateTime then value
        when Predicator::Date then Predicator::DateTime.at(value)
        when String then IsoText.read_datetime(value) || UNDEFINED
        else UNDEFINED
        end
      end

      def cast_to_duration(value)
        return DurationText.read(value) || UNDEFINED if value.is_a?(String)

        cast_duration(value) ? value : UNDEFINED
      end

      # A duration, or a map carrying the seven units read as one, or nil.
      def cast_duration(value)
        return value if value.is_a?(Duration)

        as_duration(value) if value.is_a?(Hash) && DURATION_KEYS.all? { |key| value.key?(key) }
      end
    end
    private_constant :Casts
  end
end
