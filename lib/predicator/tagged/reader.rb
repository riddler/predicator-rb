# frozen_string_literal: true

module Predicator
  module Tagged
    # Text to value: the decoding half of the codec.
    # A private constant of Tagged: its functions are reached only through
    # Tagged.decode and Tagged.encode, which document what they answer.
    #
    # @api private
    module Reader
      DURATION_UNITS = %w[years months weeks days hours minutes seconds].freeze
      DATE_TEXT = /\A(\d{4})-(\d{2})-(\d{2})\z/
      DATETIME_TEXT = /\A(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(Z|[+-]\d{2}(?::?\d{2})?)\z/
      OFFSET_TEXT = /\A([+-])(\d{2}):?(\d{2})?\z/
      READERS = { "date" => :read_date, "datetime" => :read_datetime, "duration" => :read_duration }.freeze

      module_function

      def read(text)
        utf8 = text.encoding == Encoding::UTF_8 ? text : text.dup.force_encoding(Encoding::UTF_8)
        Refused.raise!("malformed_json", "the text is not valid UTF-8") unless utf8.valid_encoding?
        value(parse(utf8), 1)
      end

      # JSON.parse keeps the written form of a number: `1` is an Integer and
      # `1.0` and `1e2` are Floats. Only an exponent too large for a Float
      # reads as an infinity, which value refuses. Its own nesting limit only
      # bounds the parser's recursion (how it counts differs between json
      # versions); value counts the levels exactly.
      def parse(text)
        JSON.parse(text, max_nesting: DEPTH_LIMIT + 2)
      rescue JSON::NestingError => e
        Refused.raise!("depth_limit_exceeded", e.message)
      rescue JSON::ParserError => e
        Refused.raise!("malformed_json", e.message)
      end

      def value(json, depth)
        case json
        when Hash then map(json, depth)
        when Array then deep(depth) && json.map { |member| value(member, depth + 1) }
        when Float then finite(json)
        else json
        end
      end

      def map(json, depth)
        deep(depth)
        return tag(json, depth) if json.key?("$type")

        json.transform_values { |member| value(member, depth + 1) }
      end

      def finite(number)
        return number if number.finite?

        Refused.raise!("non_finite_number", "the number #{number} is not finite")
      end

      def deep(depth)
        return true if depth <= DEPTH_LIMIT

        Refused.raise!("depth_limit_exceeded", "the text nests past #{DEPTH_LIMIT} levels")
      end

      # A duration's value is a map one level inside its tag's braces.
      def tag(json, depth)
        return UNDEFINED if json == { "$type" => "undefined" }

        reader = READERS[json["$type"]]
        deep(depth + 1) if reader == :read_duration
        decoded = send(reader, json["value"]) if reader && json.keys.sort == ["$type", "value"]
        decoded || Refused.raise!("invalid_tagged_value",
                                  "a #{json["$type"].inspect} tag with the keys #{json.keys.sort.inspect} " \
                                  "is not a tagged value")
      end

      def read_date(text)
        match = text.is_a?(String) && DATE_TEXT.match(text)
        return unless match

        year, month, day = match.captures.map { |part| Integer(part, 10) }
        Date.new(year:, month:, day:) if Civil.civil?(year, month, day)
      end

      # Read as the reference's ISO parser reads one: a T or a space between
      # the date and the time, any count of fraction digits (to
      # microseconds; the encoder writes none or six), and an offset other
      # than Z read as the instant it names, with "-00:00" refused. An offset
      # that moves the instant outside the years 0 to 9999 is refused, since
      # the encoder could not write it back.
      def read_datetime(text)
        match = text.is_a?(String) && DATETIME_TEXT.match(text)
        return unless match

        *parts, fraction, zone = match.captures
        offset = read_offset(zone)
        local = offset && local_instant(parts.map { |part| Integer(part, 10) }, fraction)
        local && in_carried_years(local.with(epoch_seconds: local.epoch_seconds - offset))
      end

      def in_carried_years(instant)
        instant if instant.to_date.year.between?(0, 9999)
      end

      def local_instant((year, month, day, hour, minute, second), fraction)
        return unless Civil.civil?(year, month, day) && hour <= 23 && minute <= 59 && second <= 59

        microsecond = Integer("#{fraction}000000"[0, 6], 10)
        DateTime.at(Date.new(year:, month:, day:), hour, minute, second, microsecond:)
      end

      def read_offset(zone)
        return 0 if zone == "Z"

        sign, hours, minutes = OFFSET_TEXT.match(zone).captures
        hours = hours.to_i # two digits, by OFFSET_TEXT
        minutes = minutes.to_i # two digits, or absent and zero
        seconds = (hours * 3600) + (minutes * 60)
        return if hours > 23 || minutes > 59 || (sign == "-" && seconds.zero?)

        sign == "-" ? -seconds : seconds
      end

      # The seven units are always written; milliseconds only when it is not
      # zero, so an absent one reads as zero.
      def read_duration(json)
        return unless json.is_a?(Hash) && (DURATION_UNITS - json.keys).empty?
        return unless (json.keys - DURATION_UNITS - ["milliseconds"]).empty? && json.values.all?(Integer)

        Duration.new(**json.transform_keys(&:to_sym))
      end
    end
    private_constant :Reader
  end
end
