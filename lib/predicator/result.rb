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
    # @raise [ArgumentError] when it carries both a value and an error
    def initialize(value:, error:)
      raise ArgumentError, "a result carries a value or an error, not both" unless value.nil? || error.nil?

      super
    end

    # @return [Boolean] whether the call succeeded
    def ok? = error.nil?
  end

  # The two ways the package builds a {Result}. Private to the package: a
  # host reads results and does not need to make them (Result.new and
  # Result[] stay public, as Data defines them).
  module Results
    module_function

    # A successful result.
    def ok(value) = Result.new(value:, error: nil)

    # A failed result.
    #
    # @raise [ArgumentError] when error is nil
    def failure(error)
      raise ArgumentError, "a failed result carries an error" if error.nil?

      Result.new(value: nil, error:)
    end
  end
  private_constant :Results
end
