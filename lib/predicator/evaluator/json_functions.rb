# frozen_string_literal: true

require "json"
require_relative "json_scan"

module Predicator
  module Evaluator
    # The library's JSON functions, over Ruby's standard json library (a
    # default gem, not a dependency).
    #
    # `JSON.stringify` writes a value as JSON with every map's keys in sorted
    # order, the order the conformance corpus fixes (a map has no order of
    # its own). A Float is written as the reference writes one ({FloatText}).
    # The values JSON has no form for are written as the reference writes
    # them: a date and an instant as a JSON string of their ISO 8601 text, a
    # duration as an object of its eight units, and undefined as the string
    # "undefined". A value with no JSON form at all (a map key that is not a
    # String, a String that is not valid in its encoding, an object outside
    # the value domain) is written as the value's inspect, as the reference
    # falls back to its own inspect, so the function does not fail on one.
    #
    # `JSON.parse` reads a JSON text into lists, maps with String keys and
    # scalars; a duplicated key keeps its last value. A text that is not JSON
    # is refused with the reference's sentence naming the first fault and its
    # offset in bytes ({JsonScan}): `Invalid JSON: unexpected byte 0x6F at
    # position 1`, or `Invalid JSON: unexpected end of input at position 4`.
    # Where the reference reports a sequence it cannot read (an unpaired
    # surrogate escape, a number too large for a Float), the sentence is
    # `Invalid JSON: unexpected sequence at position N`, N the offset where
    # the sequence starts.
    #
    # Both refuse a list or a map nested more than {DEPTH_LIMIT} levels deep
    # with the reason depth_limit_exceeded, the limit and the reason the
    # tagged codec keeps; the outermost list or map is level one.
    module JsonFunctions
      # The deepest level of lists and maps either function reads or writes.
      DEPTH_LIMIT = 100

      # A value with no JSON form, somewhere inside the value written.
      class NoForm < StandardError; end

      # The JSON text of value, a list or a map at level depth.
      def self.text(value, depth)
        case value
        when nil, true, false, Integer, String then string(value)
        when Float then FloatText.spell(value)
        when Array then deep(depth) && "[#{value.map { |member| text(member, depth + 1) }.join(",")}]"
        when Hash then map(value, depth)
        else tagged(value, depth)
        end
      end

      # A scalar's JSON text; a String that is not valid in its encoding has
      # none.
      def self.string(value)
        JSON.generate(value)
      rescue JSON::GeneratorError, EncodingError
        raise NoForm
      end

      def self.map(value, depth)
        deep(depth)
        raise NoForm unless value.each_key.all?(String)

        members = value.keys.sort.map { |key| "#{string(key)}:#{text(value[key], depth + 1)}" }
        "{#{members.join(",")}}"
      end

      def self.tagged(value, depth)
        case value
        when Undefined then string("undefined")
        when Predicator::Date, Predicator::DateTime then string(value.to_s)
        when Duration then map(Access::DURATION_UNITS.to_h { |unit| [unit, value.public_send(unit)] }, depth)
        else raise NoForm
        end
      end

      def self.deep(depth)
        return true if depth <= DEPTH_LIMIT

        raise Calls::Refusal, "depth_limit_exceeded"
      end

      private_class_method :string, :map, :tagged, :deep

      private

      def json_stringify(value)
        JsonFunctions.text(value, 1)
      rescue JsonFunctions::NoForm
        value.inspect
      end

      def json_parse(text)
        raise Calls::Refusal, "JSON.parse expects a string argument" unless text.is_a?(String)

        fault = JsonScan.fault(text, DEPTH_LIMIT)
        raise Calls::Refusal, fault if fault

        JSON.parse(text, max_nesting: false, allow_duplicate_key: true)
      rescue JSON::ParserError
        # The scan accepts only what the reference reads, so Ruby's parser
        # does not refuse it; if it ever does, its own text stays here.
        raise Calls::Refusal, "Invalid JSON: the text could not be read"
      end
    end
    private_constant :JsonFunctions
  end
end
