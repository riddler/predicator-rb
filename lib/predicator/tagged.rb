# frozen_string_literal: true

require "json"
require_relative "values"
require_relative "errors"
require_relative "result"

module Predicator
  # A codec for the conformance corpus's tagged-value encoding, loaded with
  # `require "predicator/tagged"` and by nothing else in the package.
  #
  # JSON carries most of predicator's values as themselves: integers, floats,
  # strings, booleans, lists, maps (objects with String keys) and null (Ruby's
  # nil). Four do not fit, and the encoding carries each as an object with a
  # `$type` key:
  #
  #   {"$type":"date","value":"2026-08-06"}                    a Predicator::Date
  #   {"$type":"datetime","value":"2026-08-06T12:00:00Z"}      a Predicator::DateTime
  #   {"$type":"duration","value":{"years":0,...,"seconds":0}} a Predicator::Duration
  #   {"$type":"undefined"}                                    Predicator::UNDEFINED
  #
  # The encoding is the corpus's apparatus, specified by predicator-ex's
  # conformance/README.md at the tag conformance/SOURCE.json names. It is
  # offered here for a host that persists instructions or values as JSON; it
  # is not part of what conformance means.
  #
  # Both directions answer a {Predicator::Result}, a failed one carrying a
  # {CodecError}, whatever the text or the value holds (decode raises
  # ArgumentError only when it is handed something other than a String);
  # {decode!} and {encode!} raise {Predicator::Error} instead. An
  # integer stays an Integer and a float a Float across a round trip: `1`
  # decodes to 1 and `1.0` to 1.0, and 1.0 encodes as `1.0`.
  module Tagged
    # The deepest a text may nest its brackets and braces, 100 levels, a
    # tag's own braces counted. Both directions hold to it, so every text
    # {encode} writes is one {decode} reads.
    DEPTH_LIMIT = 100
    private_constant :DEPTH_LIMIT

    # Why a text could not be decoded or a value encoded. Its reason is one
    # of these tokens:
    #
    # - "malformed_json": the text is not JSON (or not UTF-8)
    # - "depth_limit_exceeded": the text or value nests past 100 levels
    # - "non_finite_number": a number that is not finite
    # - "invalid_tagged_value": an object with a `$type` key that is not one
    #   of the four tags, or a tag whose value is not what the tag carries;
    #   on encode, a date or a datetime outside the years the encoding carries
    # - "reserved_map_key": on encode, a map with a `$type` key, which would
    #   read back as a tag
    # - "cyclic_value": on encode, a list or map that contains itself
    # - "unsupported_value": on encode, something that is not a predicator
    #   value (a Symbol, a map key that is not a String, a String with no
    #   UTF-8 form, any other object)
    #
    # @!attribute [r] reason
    #   @return [String] the token
    # @!attribute [r] message
    #   @return [String] a sentence for a person
    CodecError = Data.define(:reason, :message) do
      # @return [String] "CodecError"
      def type = "CodecError"
    end

    # Signals a refusal from inside a walk; never leaves this module.
    class Refused < StandardError
      attr_reader :reason

      def initialize(reason, message)
        @reason = reason
        super(message)
      end

      def self.raise!(reason, message) = raise(new(reason, message))
    end
    private_constant :Refused

    # Decodes a text in the tagged encoding into a predicator value.
    #
    # @example
    #   Predicator::Tagged.decode('{"x":{"$type":"undefined"}}').value
    #   # => {"x" => Predicator::UNDEFINED}
    #
    # @param text [String]
    # @return [Result] the value, or a {CodecError}
    # @raise [ArgumentError] when text is not a String
    def self.decode(text)
      raise ArgumentError, "decode takes a String, not #{text.class}" unless text.is_a?(String)

      refusing { Reader.read(text) }
    end

    # As {decode}, answering the value itself.
    #
    # @param text [String]
    # @return [Object] the value
    # @raise [Predicator::Error] carrying the {CodecError}
    def self.decode!(text) = unwrap(decode(text))

    # Encodes a predicator value as text in the tagged encoding.
    #
    # @example
    #   Predicator::Tagged.encode([1, 1.0, Predicator::Date.new(2026, 8, 6)]).value
    #   # => '[1,1.0,{"$type":"date","value":"2026-08-06"}]'
    #
    # @param value [Object]
    # @return [Result] the text, or a {CodecError}
    def self.encode(value) = refusing { Writer.write(value) }

    # As {encode}, answering the text itself.
    #
    # @param value [Object]
    # @return [String] the text
    # @raise [Predicator::Error] carrying the {CodecError}
    def self.encode!(value) = unwrap(encode(value))

    def self.refusing
      Result.ok(yield)
    rescue Refused => e
      Result.failure(CodecError.new(reason: e.reason, message: e.message))
    end

    def self.unwrap(result)
      raise Error, result.error unless result.ok?

      result.value
    end

    private_class_method :refusing, :unwrap
  end
end

require_relative "tagged/reader"
require_relative "tagged/writer"
