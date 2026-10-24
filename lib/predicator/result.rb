# frozen_string_literal: true

module Predicator
  # What a call answers: a value, or an error value saying why there is none.
  # Results are values, never raised; each entry point's raising variant
  # raises {Predicator::Error} carrying the same error instead.
  #
  # A successful result's value may itself be nil (predicator's null), so
  # {#ok?} is read from the error, not from the value.
  #
  # @!attribute [r] value
  #   @return [Object] the answer; nil when the result failed
  # @!attribute [r] error
  #   @return [Object, nil] the error value; nil when the result succeeded
  Result = Data.define(:value, :error) do
    # A successful result.
    #
    # @param value [Object]
    # @return [Result]
    def self.ok(value) = new(value:, error: nil)

    # A failed result.
    #
    # @param error [Object] an error value, never nil
    # @return [Result]
    def self.failure(error)
      raise ArgumentError, "a failed result carries an error" if error.nil?

      new(value: nil, error:)
    end

    # @raise [ArgumentError] when it carries both a value and an error
    def initialize(value:, error:)
      raise ArgumentError, "a result carries a value or an error, not both" unless value.nil? || error.nil?

      super
    end

    # @return [Boolean] whether the call succeeded
    def ok? = error.nil?
  end
end
