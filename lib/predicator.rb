# frozen_string_literal: true

require_relative "predicator/version"
require_relative "predicator/values"
require_relative "predicator/errors"
require_relative "predicator/result"
require_relative "predicator/evaluator"
require_relative "predicator/lexer"
require_relative "predicator/parser"
require_relative "predicator/emitter"

# A safe, non-evaluating condition language for end users.
#
# Every entry point answers a {Predicator::Result} (`ok?`, `value`, `error`)
# and never raises for an outcome of the source or the program: a source
# that does not compile, a run that stops, a value outside the domain all
# answer a failed result carrying an error value. Each has a bang variant
# (`compile!`, `evaluate!`, ...) that answers the value itself or raises
# {Predicator::Error} carrying the same error value. A caller's own bug (an
# argument of the wrong kind, an unknown or malformed option) raises
# ArgumentError.
#
# The value domain is Ruby's own values where they fit - nil (null), true and
# false, Integer and Float (kept apart), String, Array (a list) and Hash with
# String keys (a map) - plus {Predicator::UNDEFINED}, {Predicator::Date},
# {Predicator::DateTime} and {Predicator::Duration}. The codec for the
# conformance corpus's tagged encoding is loaded on its own, with
# `require "predicator/tagged"`.
#
# The options of an evaluation are keywords of the call that runs it, and
# nothing is configured globally:
#
# - `functions:` a Hash of String name to a callable (anything that responds
#   to `call`), the host's functions for this run. A function is called with
#   the call's arguments only, first argument first, each a copy, so that
#   nothing it does to one changes the context; the counts of arguments it
#   takes are read from its parameters; it refuses by raising, which fails
#   the run with an EvaluationError whose reason and message are
#   `Function NAME() raised: ` and the exception's inspect; an answer
#   outside the value domain fails the run too. A name here shadows the
#   library function of the same name, for this run only. `{}` by default.
# - `clock:` a callable answering the current time as a
#   {Predicator::DateTime}, read at most once per run and only when the
#   program reads the time; the system's real-time clock by default. One
#   that answers anything else raises ArgumentError.
# - `on_unbound:` what a load of a variable the context does not bind does:
#   `:undefined` (the default) pushes {Predicator::UNDEFINED}, and the run
#   fails with an UndefinedVariableError only if undefined is its answer;
#   `:error` fails the run at the load.
# - `loop_budget:` how many back edges (`jump_backward`) one run may take,
#   an Integer of at least 0; 10_000 by default. A run that finds it spent
#   fails with the reason `loop_budget_exceeded`.
#
# A context, and any `lit` operand of an instruction list the host built, is
# checked against the value domain before anything runs: a key that is not a
# String, a value the domain has no member for (a Symbol, a Time, any other
# object), a Float that is not finite, a list or map that contains itself or
# nests past 100 levels each fail the run with an EvaluationError (reasons
# `unsupported_host_value`, `non_finite_number`, `cyclic_value`,
# `depth_limit_exceeded`).
module Predicator
  # The instruction-set version this build emits and runs.
  #
  # @example
  #   Predicator.isa_version # => 6
  #
  # @return [Integer]
  def self.isa_version = Evaluator::ISA_VERSION

  # Compiles an expression's source to the instruction list the evaluator
  # runs. The operands are predicator values: a date literal is a
  # {Predicator::Date}, a decimal a Float, `undefined`
  # {Predicator::UNDEFINED}.
  #
  # A source that does not compile answers a failed result carrying a
  # {Predicator::ParseError}: the first refusal the scan, the parse or the
  # emit met, with its reason, the reference's message where the reference
  # has one, and its position. A statement (an assignment, an `if`, a
  # `while`) is not an expression and is refused; {compile_program} compiles
  # one.
  #
  # @example
  #   Predicator.compile("score > 85").value
  #   # => [["load", "score"], ["lit", 85], ["compare", "GT"]]
  #
  # @param source [String] the text, in UTF-8 or an encoding that converts
  #   to it
  # @return [Result] the instruction list, or the {ParseError}
  # @raise [ArgumentError] when source is not a String, or is not text in
  #   its encoding
  def self.compile(source) = compiled(source) { |tokens| Parser.parse(tokens) }

  # As {compile}, answering the instruction list itself.
  #
  # @param source [String]
  # @return [Array] the instruction list
  # @raise [Predicator::Error] carrying the {ParseError}
  # @raise [ArgumentError] as {compile} raises it
  def self.compile!(source) = unwrap(compile(source))

  # Compiles a program's source, one or more statements separated by `;`, to
  # the instruction list the evaluator runs in statement mode. A statement is
  # an assignment to a location (an identifier, a property access or a
  # bracket access), an `if` with an optional `else` or `else if`, a
  # `while`, or an expression whose value is discarded. Every statement
  # leaves the stack as it found it: an assignment ends in a `store`, an
  # expression in a `pop`.
  #
  # A source that does not compile answers a failed result carrying a
  # {Predicator::ParseError}, as {compile} does.
  #
  # @example
  #   Predicator.compile_program("x = 1; x + 1").value
  #   # => [["lit", "x"], ["lit", 1], ["store", 1], ["load", "x"], ["lit", 1], ["add"], ["pop"]]
  #
  # @param source [String] the text, in UTF-8 or an encoding that converts
  #   to it
  # @return [Result] the instruction list, or the {ParseError}
  # @raise [ArgumentError] when source is not a String, or is not text in
  #   its encoding
  def self.compile_program(source) = compiled(source, program: true) { |tokens| Parser.parse_program(tokens) }

  # As {compile_program}, answering the instruction list itself.
  #
  # @param source [String]
  # @return [Array] the instruction list
  # @raise [Predicator::Error] carrying the {ParseError}
  # @raise [ArgumentError] as {compile_program} raises it
  def self.compile_program!(source) = unwrap(compile_program(source))

  # Runs an expression against a context and answers its value: the top of
  # the stack at halt. The program is an instruction list, or an
  # expression's source, which is compiled as {compile} compiles it (a
  # source that does not compile answers its {ParseError}).
  #
  # A run that stops answers the error value that stopped it: an
  # {EvaluationError}, a {TypeMismatchError} or an
  # {UndefinedVariableError}. An empty stack at halt is an error, and so is
  # undefined at halt when a load did not find its variable.
  #
  # @example
  #   Predicator.evaluate("score > 85", { "score" => 90 }).value # => true
  #   Predicator.evaluate([["load", "x"], ["lit", 1], ["add"]], { "x" => 2 }).value # => 3
  #
  # @param program [Array, String] an instruction list, or an expression's
  #   source
  # @param context [Hash{String => Object}] the variables a load reads
  # @param options [Hash] `functions:`, `clock:`, `on_unbound:` and
  #   `loop_budget:`, as {Predicator} describes them
  # @return [Result] the value, or the error value
  # @raise [ArgumentError] when the program or the context is not of its
  #   kind, an option is unknown or malformed, or the clock answers something
  #   other than a {Predicator::DateTime}
  def self.evaluate(program, context = {}, **)
    instructions = instructions_of(program) { |source| compile(source) }
    return instructions if instructions.is_a?(Result)

    refused = refusal_of(instructions, context)
    refused ? Result.failure(refused) : Evaluator.evaluate(instructions, context, **)
  end

  # As {evaluate}, answering the value itself.
  #
  # @param program [Array, String]
  # @param context [Hash{String => Object}]
  # @param options [Hash] as {evaluate} takes them
  # @return [Object] the value
  # @raise [Predicator::Error] carrying the error value
  # @raise [ArgumentError] as {evaluate} raises it
  def self.evaluate!(program, context = {}, **) = unwrap(evaluate(program, context, **))

  # Runs a statement program against a context and answers the context at
  # halt, a Hash holding every write the program made. The program is an
  # instruction list, or a program's source, which is compiled as
  # {compile_program} compiles it. The context passed is never changed: a
  # write builds a new one, and when nothing is written the context at halt
  # is the one passed. An empty stack at halt is a normal halt.
  #
  # A run that stops answers the error value that stopped it, and no
  # context.
  #
  # @example
  #   Predicator.execute("x = 1; y = x + 2").value # => {"x" => 1, "y" => 3}
  #
  # @param program [Array, String] an instruction list, or a program's
  #   source
  # @param context [Hash{String => Object}] the variables a load reads
  # @param options [Hash] as {evaluate} takes them
  # @return [Result] the context at halt, or the error value
  # @raise [ArgumentError] as {evaluate} raises it
  def self.execute(program, context = {}, **)
    ran = statements(program, context, **)
    return ran if ran.is_a?(Result)

    ran.ok? ? Result.ok(ran.context) : Result.failure(ran.error)
  end

  # As {execute}, answering the context itself.
  #
  # @param program [Array, String]
  # @param context [Hash{String => Object}]
  # @param options [Hash] as {evaluate} takes them
  # @return [Hash] the context at halt
  # @raise [Predicator::Error] carrying the error value
  # @raise [ArgumentError] as {evaluate} raises it
  def self.execute!(program, context = {}, **) = unwrap(execute(program, context, **))

  # Runs a statement program as {execute} does and answers a pair: the value
  # of its last expression statement (the value the last `pop` discarded,
  # {Predicator::UNDEFINED} when no expression statement ran) and the context
  # at halt.
  #
  # A run that stops answers the error value that stopped it, and neither a
  # value nor a context.
  #
  # @example
  #   value, context = Predicator.execute_value!("x = 2; x * 10")
  #   value   # => 20
  #   context # => {"x" => 2}
  #
  # @param program [Array, String] an instruction list, or a program's
  #   source
  # @param context [Hash{String => Object}] the variables a load reads
  # @param options [Hash] as {evaluate} takes them
  # @return [Result] the pair `[value, context]`, or the error value
  # @raise [ArgumentError] as {evaluate} raises it
  def self.execute_value(program, context = {}, **)
    ran = statements(program, context, **)
    return ran if ran.is_a?(Result)

    ran.ok? ? Result.ok([ran.value, ran.context]) : Result.failure(ran.error)
  end

  # As {execute_value}, answering the pair itself.
  #
  # @param program [Array, String]
  # @param context [Hash{String => Object}]
  # @param options [Hash] as {evaluate} takes them
  # @return [Array] the pair `[value, context]`
  # @raise [Predicator::Error] carrying the error value
  # @raise [ArgumentError] as {evaluate} raises it
  def self.execute_value!(program, context = {}, **) = unwrap(execute_value(program, context, **))

  # Parses an expression's source to its syntax tree, without compiling it:
  # the first two of the three stages {compile} runs, so a source this
  # refuses, {compile} refuses with the same {ParseError}. The converse does
  # not hold: the third stage, the emitter, refuses a decimal literal too
  # large for a finite Float (`number_out_of_range`), and a tree whose walk
  # runs out of stack (`nesting_depth_exceeded`), and such a source parses
  # here.
  #
  # The tree is the reference's: each node an immutable value of the node's
  # kind, carrying its fields, its position and its span. The node classes
  # are private to the package, and the tree's shape is not a compatibility
  # promise: it may change in a minor version.
  #
  # @param source [String] the text, in UTF-8 or an encoding that converts
  #   to it
  # @return [Result] the root node of the tree, or the {ParseError}
  # @raise [ArgumentError] as {compile} raises it
  def self.parse(source)
    tokens = Lexer.tokenize(text_of(source))
    tree = refused?(tokens) ? tokens : Parser.parse(tokens)
    refused?(tree) ? failed(tree) : Result.ok(tree)
  end

  # As {parse}, answering the tree itself.
  #
  # @param source [String]
  # @return [Object] the root node of the tree
  # @raise [Predicator::Error] carrying the {ParseError}
  # @raise [ArgumentError] as {compile} raises it
  def self.parse!(source) = unwrap(parse(source))

  # Reads a duration from its literal spelling, such as `"3d8h30m"` or
  # `"1.5s"`: the spelling the `::duration` cast reads and the `::string`
  # cast writes. It is one or more components, each a whole number with an
  # optional decimal fraction followed by one of the units `y`, `mo`, `w`,
  # `d`, `h`, `m`, `s` and `ms`, with no whitespace, no sign and no empty
  # text. A repeated unit adds to what came before; a fraction expands into
  # whole smaller units (a month 30 days, a year 365), and one that is not a
  # whole number of milliseconds is refused.
  #
  # A text that does not spell a duration answers a failed result carrying
  # an {EvaluationError} with the reason `invalid_duration_format`.
  #
  # @example
  #   Predicator.parse_duration("1h30m").value.minutes # => 30
  #
  # @param text [String]
  # @return [Result] the {Predicator::Duration}, or the error value
  # @raise [ArgumentError] when text is not a String, or is not text in its
  #   encoding
  def self.parse_duration(text)
    duration = DurationText.read(text_of(text))
    return Result.ok(duration) if duration

    Result.failure(EvaluationError.new(reason: "invalid_duration_format",
                                       message: "Invalid duration format: #{text}"))
  end

  # As {parse_duration}, answering the duration itself.
  #
  # @param text [String]
  # @return [Duration]
  # @raise [Predicator::Error] carrying the error value
  # @raise [ArgumentError] as {parse_duration} raises it
  def self.parse_duration!(text) = unwrap(parse_duration(text))

  # Scans the source, parses its tokens with the block and emits the tree,
  # answering the first refusal of the three.
  def self.compiled(source, program: false)
    tokens = Lexer.tokenize(text_of(source))
    tree = refused?(tokens) ? tokens : yield(tokens)
    entries = if refused?(tree) then tree
              elsif program then Emitter.emit_program(tree)
              else Emitter.emit(tree)
              end
    return failed(entries) if refused?(entries)

    Result.ok(entries.map(&:instruction))
  end

  def self.refused?(stage) = stage.is_a?(Lexer::Refusal)
  def self.failed(refusal) = Result.failure(refusal.error)

  # The source as valid UTF-8: bytes with no encoding of their own (binary
  # or US-ASCII) are read as UTF-8, and text in any other encoding is
  # converted to it.
  def self.text_of(source)
    raise ArgumentError, "a source is a String, not #{source.class}" unless source.is_a?(String)

    text = if [Encoding::BINARY, Encoding::US_ASCII].include?(source.encoding)
             source.dup.force_encoding(Encoding::UTF_8)
           else
             source.encode(Encoding::UTF_8)
           end
    return text if text.valid_encoding?

    raise ArgumentError, "a source is text, and this one is not valid #{text.encoding}"
  rescue EncodingError => e
    raise ArgumentError, "a source is text that converts to UTF-8: #{e.message}"
  end

  # The instruction list a program names: the list itself, or the source
  # compiled by the block, or the failed result of a source that does not
  # compile.
  def self.instructions_of(program)
    return program unless program.is_a?(String)

    compiled = yield(program)
    compiled.ok? ? compiled.value : compiled
  end

  # A statement-mode run of a program, or the failed result of a source
  # that does not compile.
  def self.statements(program, context, **)
    instructions = instructions_of(program) { |source| compile_program(source) }
    return instructions if instructions.is_a?(Result)

    refused = refusal_of(instructions, context)
    refused ? Result.failure(refused) : Evaluator.execute(instructions, context, **)
  end

  # The refusal of a context or a literal operand outside the value domain,
  # or nil. Arguments of the wrong kind are left for the evaluator to raise
  # on.
  def self.refusal_of(instructions, context)
    Boundary.input_refusal(instructions, context) if instructions.is_a?(Array) && context.is_a?(Hash)
  end

  # The value of a result, or the raise of its error.
  def self.unwrap(result)
    raise Error, result.error unless result.ok?

    result.value
  end

  private_class_method :compiled, :refused?, :failed, :text_of, :instructions_of, :statements, :refusal_of, :unwrap
end
