# frozen_string_literal: true

module Predicator
  module Tagged
    # Value to text: the encoding half of the codec.
    # A private constant of Tagged: its functions are reached only through
    # Tagged.decode and Tagged.encode, which document what they answer.
    #
    # @api private
    module Writer
      DURATION_UNITS = %w[years months weeks days hours minutes seconds].freeze
      LITERALS = { nil => "null", true => "true", false => "false" }.freeze

      module_function

      def write(value) = text(value, 1, {}.compare_by_identity)

      def text(value, depth, ancestors)
        return LITERALS.fetch(value) if LITERALS.key?(value)

        case value
        when Integer then value.to_s
        when Float then float(value)
        when String then string(value)
        when Array, Hash then container(value, depth, ancestors)
        else tag(value, depth)
        end
      end

      def float(value)
        Refused.raise!("non_finite_number", "the float #{value} is not finite") unless value.finite?
        value.to_s
      end

      # A String in another encoding is written as its UTF-8 transcoding; one
      # that is not valid in its own encoding, or has no UTF-8 form, is not a
      # predicator string.
      def string(value)
        utf8 = value.valid_encoding? ? value.encode(Encoding::UTF_8) : nil
        JSON.generate(utf8 || Refused.raise!("unsupported_value", "#{value.inspect} has no UTF-8 form"))
      rescue EncodingError
        Refused.raise!("unsupported_value", "#{value.inspect} has no UTF-8 form")
      end

      def container(value, depth, ancestors)
        deep(depth)
        Refused.raise!("cyclic_value", "the value contains itself") if ancestors.key?(value)

        ancestors[value] = true
        written = value.is_a?(Array) ? list(value, depth, ancestors) : map(value, depth, ancestors)
        ancestors.delete(value)
        written
      end

      def deep(depth)
        Refused.raise!("depth_limit_exceeded", "the value nests past #{DEPTH_LIMIT} levels") if depth > DEPTH_LIMIT
      end

      def list(list, depth, ancestors)
        "[#{list.map { |member| text(member, depth + 1, ancestors) }.join(",")}]"
      end

      def map(map, depth, ancestors)
        Refused.raise!("reserved_map_key", "a map with a \"$type\" key would read back as a tag") if map.key?("$type")

        members = map.map do |key, member|
          Refused.raise!("unsupported_value", "a map key is a String, not #{key.inspect}") unless key.is_a?(String)
          "#{string(key)}:#{text(member, depth + 1, ancestors)}"
        end
        "{#{members.join(",")}}"
      end

      # A tag is one level of braces; a duration's value is a second.
      def tag(value, depth)
        written = tag_text(value)
        deep(depth + (value.is_a?(Duration) ? 1 : 0))
        written
      end

      def tag_text(value)
        case value
        when Undefined then '{"$type":"undefined"}'
        when Date then %({"$type":"date","value":"#{carried(value, value.year)}"})
        when DateTime then %({"$type":"datetime","value":"#{carried(value, value.to_date.year)}"})
        when Duration then duration(value)
        else Refused.raise!("unsupported_value", "#{value.inspect} is not a predicator value")
        end
      end

      # The encoding carries four-digit years; a date or an instant outside
      # them has no text that reads back as itself.
      def carried(value, year)
        return value.to_s if year.between?(0, 9999)

        Refused.raise!("invalid_tagged_value", "#{value.inspect} is outside the years 0 to 9999 the encoding carries")
      end

      def duration(value)
        units = DURATION_UNITS.map { |unit| %("#{unit}":#{value.public_send(unit)}) }
        units << %("milliseconds":#{value.milliseconds}) unless value.milliseconds.zero?
        %({"$type":"duration","value":{#{units.join(",")}}})
      end
    end
    private_constant :Writer
  end
end
