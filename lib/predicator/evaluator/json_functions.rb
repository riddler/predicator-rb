# frozen_string_literal: true

require "json"
require "strscan"
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
    # scalars; a key an object repeats keeps its first value, as the
    # reference reads one ({JsonRead}). A text that is not JSON
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
        when Duration then map(Access.units(value), depth)
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

        JsonRead.new(text).value
      rescue JSON::ParserError
        # The scan accepts only what the reference reads, so Ruby's parser
        # does not refuse a scalar of it; if it ever does, its own text stays
        # here.
        raise Calls::Refusal, "Invalid JSON: the text could not be read"
      end
    end
    private_constant :JsonFunctions

    # Reads a JSON text {JsonScan} has accepted, its bytes read as UTF-8,
    # into lists, maps and scalars. Each scalar's own text is read by Ruby's
    # json library; the lists and maps are built here, because that library
    # keeps the last value of a key an object repeats and the reference
    # keeps the first. The scan has bounded the nesting, so the reader
    # recurses.
    class JsonRead
      # The bytes a JSON text may hold between tokens.
      SPACE = /[ \t\n\r]*/
      # A scalar's text: a string, a number or a literal.
      SCALAR = /"(?:[^"\\]|\\.)*"|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|true|false|null/n

      def initialize(text)
        @scanner = StringScanner.new(text.b)
      end

      # The value at the scan, and past it.
      def value
        @scanner.skip(SPACE)
        if @scanner.skip("[") then list
        elsif @scanner.skip("{") then map
        else JSON.parse(@scanner.scan(SCALAR).force_encoding(Encoding::UTF_8))
        end
      end

      private

      def list
        items = []
        items << value until closed?("]")
        items
      end

      def map
        members = {}
        until closed?("}")
          key = value
          @scanner.skip(SPACE)
          @scanner.skip(":")
          member = value
          members[key] = member unless members.key?(key)
        end
        members
      end

      # Whether the container closes here, past a comma between members.
      def closed?(closer)
        @scanner.skip(SPACE)
        @scanner.skip(",")
        @scanner.skip(SPACE)
        !@scanner.skip(closer).nil?
      end
    end
    private_constant :JsonRead
  end
end
