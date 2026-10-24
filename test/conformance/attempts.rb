# frozen_string_literal: true

require_relative "../../lib/predicator"

module Conformance
  # THE SEAM: what each surface does with one case. It is the one place the
  # library is plugged into the run; the runner, the registry check and the
  # ratchet all reach the library through ALL and nothing else.
  #
  # An attempt is a callable taking a case (the parsed tier-file line) and
  # answering :pass, or a String saying why the case failed. Anything other
  # than :pass is a fail, and an attempt that raises is a fail naming the
  # exception: a case is never skipped and never aborts the run (the
  # never-skip rule of the reference's conformance/README.md).
  #
  # A case reaches an attempt already decoded through Predicator::Tagged
  # (Corpus.parse_line): its instructions, context and expected_result hold
  # predicator values, not the encoding's tags.
  #
  # The evaluator surface runs the case's instructions and context through
  # Predicator.evaluate, under the default unbound policy (the corpus runs
  # every case under the default option), and compares the answer with
  # expected_result, or the error's type and reason with expected_error.
  # The compiler surface compiles the case's source with Predicator.compile
  # and compares the instruction list with the case's instructions, operand
  # by operand as identical? judges them (an Integer is not a Float, a date
  # is not a datetime).
  module Attempts
    # The instruction-set version this package claims, which scopes which
    # cases a run attempts (Corpus#runnable). It is the package's version, read
    # from Predicator.isa_version, not the vendored corpus's: the two are read
    # separately even while they agree.
    ISA_VERSION = Predicator.isa_version

    # The evaluator surface's attempt of one case.
    def self.evaluate(item)
      result = Predicator.evaluate(item["instructions"], item["context"])
      item.key?("expected_error") ? error_answer(result, item["expected_error"]) : value_answer(result, item)
    end

    def self.value_answer(result, item)
      expected = item["expected_result"]
      return "failed with #{described(result.error)}; expected #{expected.inspect}" unless result.ok?
      return :pass if identical?(result.value, expected)

      "answered #{result.value.inspect}; expected #{expected.inspect}"
    end

    def self.error_answer(result, expected)
      wanted = "#{expected["type"]} #{expected["reason"]}"
      return "answered #{result.value.inspect}; expected #{wanted}" if result.ok?
      return :pass if described(result.error) == wanted

      "failed with #{described(result.error)}; expected #{wanted}"
    end

    def self.described(error) = "#{error.type} #{error.reason}"

    # Whether actual is the very value expected: the same member of the
    # domain (an Integer is not a Float, a date is not a datetime) holding
    # the same value, at every depth. Written here, not borrowed from the
    # evaluator's own equality, so the run does not judge the evaluator by
    # itself.
    def self.identical?(actual, expected)
      return false unless actual.instance_of?(expected.class)

      case expected
      when Array then actual.size == expected.size && actual.zip(expected).all? { |a, e| identical?(a, e) }
      when Hash then identical_maps?(actual, expected)
      else actual == expected
      end
    end

    def self.identical_maps?(actual, expected)
      actual.keys.sort == expected.keys.sort && expected.all? { |key, value| identical?(actual[key], value) }
    end

    # The compiler surface's attempt of one case.
    def self.compile(item)
      result = Predicator.compile(item["source"])
      expected = item["instructions"]
      return "refused with #{described(result.error)}: #{result.error.message}" unless result.ok?
      return :pass if identical?(result.value, expected)

      "compiled to #{result.value.inspect}; expected #{expected.inspect}"
    end

    # The attempt each surface makes of a case.
    ALL = {
      "compiler" => ->(item) { compile(item) },
      "evaluator" => ->(item) { evaluate(item) }
    }.freeze
  end
end
