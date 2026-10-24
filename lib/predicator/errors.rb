# frozen_string_literal: true

module Predicator
  # A place in source text: a line and a column, both counted from 1. The
  # reference reports positions in this shape.
  #
  # @!attribute [r] line
  #   @return [Integer] the line, from 1
  # @!attribute [r] column
  #   @return [Integer] the column, from 1
  Position = Data.define(:line, :column) do
    # @raise [ArgumentError] unless both are Integers of at least 1
    def initialize(line:, column:)
      unless [line, column].all? { |part| part.is_a?(Integer) && part >= 1 }
        raise ArgumentError, "a position is a line and a column from 1, not #{[line, column].inspect}"
      end

      super
    end
  end

  # What every error value has, built into each of the four classes below.
  # The type names the class, and with the reason it is normative: the
  # conformance corpus matches an expected error on exactly those two. The
  # message is for a person and is not normative. The position is where in
  # the source the failure is, where the reference gives one.
  module ErrorValue
    # The error's type as the corpus spells it, which is its class's name.
    #
    # @return [String]
    def type = self.class.name.delete_prefix("Predicator::")

    private

    def check(reason, message, position, position_required: false)
      raise ArgumentError, "reason must be a String, not #{reason.inspect}" unless reason.is_a?(String)
      raise ArgumentError, "message must be a String, not #{message.inspect}" unless message.is_a?(String)
      return if position.is_a?(Position) || (position.nil? && !position_required)

      raise ArgumentError, "position must be a Predicator::Position#{" or nil" unless position_required}, " \
                           "not #{position.inspect}"
    end
  end
  private_constant :ErrorValue

  # A source text that does not parse. It is not an evaluation outcome, so
  # the corpus never expects one; its reason is this package's own token for
  # the refusal, and it always knows its position.
  #
  # @!attribute [r] reason
  #   @return [String] a structured token naming the refusal
  # @!attribute [r] message
  #   @return [String] a sentence for a person; not normative
  # @!attribute [r] position
  #   @return [Position] where in the source the refusal is
  ParseError = Data.define(:reason, :message, :position) do
    include ErrorValue

    # @raise [ArgumentError] when a field has the wrong type
    def initialize(reason:, message:, position:)
      check(reason, message, position, position_required: true)
      super
    end
  end

  # An evaluation failure that is neither a type mismatch nor an unbound
  # variable: an empty stack at halt, too few operands, an unknown
  # instruction, a division by zero, a failed call.
  #
  # @!attribute [r] reason
  #   @return [String] the normative reason token, e.g. "division_by_zero"
  # @!attribute [r] message
  #   @return [String] a sentence for a person; not normative
  # @!attribute [r] position
  #   @return [Position, nil] where in the source the failing instruction
  #     came from, when that is known
  EvaluationError = Data.define(:reason, :message, :position) do
    include ErrorValue

    # @raise [ArgumentError] when a field has the wrong type
    def initialize(reason:, message:, position: nil)
      check(reason, message, position)
      super
    end
  end

  # An operand an opcode refused on its type. The reason is the operation
  # that refused it, e.g. "add".
  #
  # @!attribute [r] reason
  #   @return [String] the normative reason token
  # @!attribute [r] message
  #   @return [String] a sentence for a person; not normative
  # @!attribute [r] position
  #   @return [Position, nil] where in the source, when that is known
  TypeMismatchError = Data.define(:reason, :message, :position) do
    include ErrorValue

    # @raise [ArgumentError] when a field has the wrong type
    def initialize(reason:, message:, position: nil)
      check(reason, message, position)
      super
    end
  end

  # A variable the context does not bind, reported as an error rather than
  # as undefined.
  #
  # @!attribute [r] reason
  #   @return [String] the normative reason token, e.g. "unbound_variable"
  # @!attribute [r] message
  #   @return [String] a sentence for a person; not normative
  # @!attribute [r] position
  #   @return [Position, nil] where in the source, when that is known
  UndefinedVariableError = Data.define(:reason, :message, :position) do
    include ErrorValue

    # @raise [ArgumentError] when a field has the wrong type
    def initialize(reason:, message:, position: nil)
      check(reason, message, position)
      super
    end
  end

  # The exception a raising variant raises. It carries the error value a
  # result would have answered, so a caller that rescues it reads the same
  # type, reason and position.
  class Error < StandardError
    # @return [Object] the error value: a {ParseError}, an
    #   {EvaluationError}, a {TypeMismatchError}, an
    #   {UndefinedVariableError}, or a {Predicator::Tagged::CodecError}
    attr_reader :error

    # @param error [Object] an error value; its message is the exception's
    def initialize(error)
      @error = error
      super(error.message)
    end
  end
end
