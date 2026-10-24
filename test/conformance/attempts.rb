# frozen_string_literal: true

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
  # Nothing is implemented yet, so both surfaces answer a fail naming the gap
  # for every case, and no case can enter the registry. The change that adds
  # the evaluator replaces the "evaluator" lambda with one that runs the
  # case's instructions and context through the public evaluate entry point,
  # and compares the answer with expected_result, or the error's type and
  # reason with expected_error; the change that adds the
  # compiler does the same for "compiler", comparing its compilation of the
  # case's source with the case's instructions. ISA_VERSION gives way to the
  # package's own accessor when the public surface has one.
  module Attempts
    # The instruction-set version this package claims, which scopes which
    # cases a run attempts (Corpus#runnable). It is the package's version, not
    # the vendored corpus's: the two are read separately even while they agree.
    ISA_VERSION = 6

    # The attempt each surface makes of a case.
    ALL = {
      "compiler" => ->(_item) { "the compiler is not implemented" },
      "evaluator" => ->(_item) { "the evaluator is not implemented" }
    }.freeze
  end
end
