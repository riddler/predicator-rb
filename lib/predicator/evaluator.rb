# frozen_string_literal: true

require_relative "values"
require_relative "errors"
require_relative "result"
require_relative "float_text"
require_relative "duration_text"
require_relative "iso_text"
require_relative "boundary"
require_relative "evaluator/chronology"
require_relative "evaluator/arithmetic"
require_relative "evaluator/access"
require_relative "evaluator/rich_types"
require_relative "evaluator/library"
require_relative "evaluator/calls"
require_relative "evaluator/statements"
require_relative "evaluator/casts"

module Predicator
  # The stack machine that runs an instruction list against a context. It
  # runs in one of two modes, carried by the entry point and not by the
  # list: in expression mode ({evaluate}) the answer is the top of the stack
  # at halt; in statement mode ({execute}) it is the context at halt. The
  # instructions mean the same in both. It is private to the package: the
  # public entry points ({Predicator.evaluate}, {Predicator.execute} and
  # {Predicator.execute_value}) check what they are handed against the
  # value domain ({Boundary}) and then call it.
  #
  # A program is a flat list of instructions run in order from index 0; it
  # halts when the instruction pointer reaches or passes the end, so a jump
  # past the last instruction is a normal halt. The rules every opcode keeps
  # are the reference's ISA (docs/isa.md, section 2): opcodes validate and
  # never coerce; a malformed operand is an unknown instruction; stack depth
  # is checked before types.
  #
  # Each instruction this build runs is one row of {INSTRUCTIONS}: the shapes
  # of its operands, the instruction-set version that retired it, and the
  # Machine method that runs it. A later opcode is one more row and one more
  # method; the loop, the operand check and the halt rules do not change.
  #
  # Options are per call: nothing here is configured globally, and every
  # evaluation builds its own Machine. That includes the clock: an
  # instruction that reads the time reads the clock the caller passed, at
  # most once per evaluation, so every such instruction in one evaluation
  # reads the same instant. It includes the host's functions too: `call`
  # reaches the ones the caller passed to this evaluation, then the
  # package's own library, and nothing registered anywhere else. And it
  # includes the loop budget: the back edges one evaluation may take.
  module Evaluator
    # The instruction-set version this build runs: an opcode retired at or
    # below it is refused.
    ISA_VERSION = 6

    # What a load of a root the context does not bind does: :undefined
    # pushes undefined (and the answer is an unbound-variable error if
    # undefined is what the program answers); :error stops at the load.
    UNBOUND_POLICIES = %i[undefined error].freeze

    # The back edges (`jump_backward`) one evaluation may take when the
    # caller names no budget, the reference's default.
    DEFAULT_LOOP_BUDGET = 10_000

    # The clock an evaluation reads when the caller passes none: the system's
    # real-time clock, read to the microsecond, as an instant in UTC. It
    # holds no state.
    SYSTEM_CLOCK = lambda do
      micros = Process.clock_gettime(Process::CLOCK_REALTIME, :microsecond)
      Predicator::DateTime.new(epoch_seconds: micros.div(1_000_000), microsecond: micros % 1_000_000)
    end

    # One instruction's row: the shape of each operand, the version that
    # retired it (nil while it is live) and the Machine method that runs it.
    Row = Data.define(:operands, :removed_in, :handler) do
      # Whether the opcode was retired at or below {ISA_VERSION}.
      def retired? = !removed_in.nil? && removed_in <= ISA_VERSION
    end

    # Each operand shape, as a test of one operand.
    SHAPES = {
      value: ->(_operand) { true },
      string: ->(operand) { operand.is_a?(String) },
      list: ->(operand) { operand.is_a?(Array) },
      comparison_operator: ->(operand) { Compare::OPERATORS.include?(operand) },
      positive_integer: ->(operand) { operand.is_a?(Integer) && operand.positive? },
      count: ->(operand) { operand.is_a?(Integer) && !operand.negative? },
      type_name: ->(operand) { Casts::TYPE_NAMES.include?(operand) }
    }.freeze

    # The instructions this build knows, by opcode. `and` and `or` were
    # retired at instruction-set version 3; they keep their rows so that a
    # list carrying them is refused as retired rather than as unknown.
    INSTRUCTIONS = {
      "lit" => Row.new(operands: [:value], removed_in: nil, handler: :push),
      "load" => Row.new(operands: [:string], removed_in: nil, handler: :load_root),
      "compare" => Row.new(operands: [:comparison_operator], removed_in: nil, handler: :compare),
      "not" => Row.new(operands: [], removed_in: nil, handler: :logical_not),
      "unary_bang" => Row.new(operands: [], removed_in: nil, handler: :unary_bang),
      "unary_minus" => Row.new(operands: [], removed_in: nil, handler: :unary_minus),
      "jump_if_falsy_or_pop" => Row.new(operands: [:positive_integer], removed_in: nil,
                                        handler: :jump_if_falsy_or_pop),
      "jump_if_true_or_pop" => Row.new(operands: [:positive_integer], removed_in: nil,
                                       handler: :jump_if_true_or_pop),
      "add" => Row.new(operands: [], removed_in: nil, handler: :add),
      "subtract" => Row.new(operands: [], removed_in: nil, handler: :subtract),
      "multiply" => Row.new(operands: [], removed_in: nil, handler: :multiply),
      "divide" => Row.new(operands: [], removed_in: nil, handler: :divide),
      "modulo" => Row.new(operands: [], removed_in: nil, handler: :modulo),
      "access" => Row.new(operands: [:string], removed_in: nil, handler: :access),
      "bracket_access" => Row.new(operands: [], removed_in: nil, handler: :bracket_access),
      "in" => Row.new(operands: [], removed_in: nil, handler: :membership_in),
      "contains" => Row.new(operands: [], removed_in: nil, handler: :membership_contains),
      "make_list" => Row.new(operands: [:count], removed_in: nil, handler: :make_list),
      "duration" => Row.new(operands: [:list], removed_in: nil, handler: :duration),
      "relative_date" => Row.new(operands: [:string], removed_in: nil, handler: :relative_date),
      "object_new" => Row.new(operands: [], removed_in: nil, handler: :object_new),
      "object_set" => Row.new(operands: [:string], removed_in: nil, handler: :object_set),
      "call" => Row.new(operands: %i[string count], removed_in: nil, handler: :call_function),
      "store" => Row.new(operands: [:count], removed_in: nil, handler: :store),
      "pop" => Row.new(operands: [], removed_in: nil, handler: :discard),
      "jump" => Row.new(operands: [:positive_integer], removed_in: nil, handler: :jump),
      "pop_jump_if_falsy" => Row.new(operands: [:positive_integer], removed_in: nil, handler: :pop_jump_if_falsy),
      "jump_backward" => Row.new(operands: [:positive_integer], removed_in: nil, handler: :jump_backward),
      "cast" => Row.new(operands: [:type_name], removed_in: nil, handler: :cast),
      "and" => Row.new(operands: [], removed_in: 3, handler: nil),
      "or" => Row.new(operands: [], removed_in: 3, handler: nil)
    }.freeze

    # The options one evaluation runs under, checked: the unbound policy,
    # the clock, the host's functions and the loop budget.
    Settings = Data.define(:on_unbound, :clock, :functions, :loop_budget)
    private_constant :Settings

    # What a run in statement mode answers: the context at halt and the
    # value the last `pop` discarded (undefined when no `pop` ran), or the
    # error that stopped the run and the context as it stood then, which
    # holds every write made before the failing instruction.
    #
    # @!attribute [r] error
    #   @return [Object, nil] the error value that stopped the run, or nil
    # @!attribute [r] context
    #   @return [Hash] the context at halt, or when the run stopped
    # @!attribute [r] value
    #   @return [Object] what the last `pop` discarded, or undefined
    StatementResult = Data.define(:error, :context, :value) do
      # Whether the run reached its halt.
      def ok? = error.nil?
    end

    # Runs instructions against context in expression mode: the answer is
    # the top of the stack at halt.
    #
    # @param instructions [Array] the instruction list
    # @param context [Hash{String => Object}] the variables a load reads
    # @param options [Hash] the evaluation's options, each optional:
    # @option options [Symbol] :on_unbound one of {UNBOUND_POLICIES};
    #   :undefined when not given
    # @option options [#call, nil] :clock the clock: called with no argument,
    #   it answers the current time as a {Predicator::DateTime}. It is called
    #   at most once, and only when an instruction reads the time. nil, the
    #   default, means {SYSTEM_CLOCK}. A clock that answers anything else, or
    #   raises a StandardError, stops the run with an EvaluationError whose
    #   reason is clock_failed, whichever instruction read it.
    # @option options [Hash{String => #call}] :functions the host's functions
    #   for this evaluation, by the name a `call` instruction names. Each is
    #   called with the call's arguments, first argument first, and answers
    #   the call's value; the counts of arguments it accepts are the ones its
    #   parameters take. A name here shadows the library function of the
    #   same name, for this evaluation only. {Calls} says how a call is
    #   refused.
    # @option options [Integer] :loop_budget the back edges the evaluation
    #   may take, at least 0; {DEFAULT_LOOP_BUDGET} when not given. A
    #   `jump_backward` that finds the budget spent stops the run with
    #   loop_budget_exceeded.
    # @return [Result] the top of the stack at halt, or the error that
    #   stopped the run
    # @raise [ArgumentError] when an argument is not of its kind, or an
    #   option is unknown or malformed (a caller's bug, not an outcome of the
    #   program)
    def self.evaluate(instructions, context = {}, **options) = machine(instructions, context, options).run

    # Runs instructions against context in statement mode: the answer is
    # the context at halt. An empty stack at halt is a normal halt, and
    # whatever the stack holds then is discarded. The context passed is
    # never changed; a `store` writes a new one.
    #
    # @param instructions [Array] the instruction list
    # @param context [Hash{String => Object}] the variables a load reads
    # @param options [Hash] the options {evaluate} takes
    # @return [StatementResult] the context at halt and the value the last `pop`
    #   discarded, or the error that stopped the run
    # @raise [ArgumentError] as {evaluate} raises it
    def self.execute(instructions, context = {}, **options)
      machine(instructions, context, options).run_statements
    end

    def self.machine(instructions, context, options)
      raise ArgumentError, "instructions must be an Array, not #{instructions.inspect}" unless instructions.is_a?(Array)
      raise ArgumentError, "context must be a Hash, not #{context.inspect}" unless context.is_a?(Hash)

      Machine.new(instructions, context, settings(**options))
    end
    private_class_method :machine

    def self.settings(on_unbound: :undefined, clock: nil, functions: {}, loop_budget: DEFAULT_LOOP_BUDGET)
      unless UNBOUND_POLICIES.include?(on_unbound)
        raise ArgumentError, "on_unbound must be one of #{UNBOUND_POLICIES.inspect}, not #{on_unbound.inspect}"
      end
      raise ArgumentError, "clock must respond to call, not #{clock.inspect}" unless clock?(clock)
      unless loop_budget.is_a?(Integer) && !loop_budget.negative?
        raise ArgumentError, "loop_budget must be an Integer of at least 0, not #{loop_budget.inspect}"
      end

      check_functions(functions)
      Settings.new(on_unbound:, clock: clock || SYSTEM_CLOCK, functions:, loop_budget:)
    end
    private_class_method :settings

    def self.clock?(clock) = clock.nil? || clock.respond_to?(:call)
    private_class_method :clock?

    def self.check_functions(functions)
      raise ArgumentError, "functions must be a Hash, not #{functions.inspect}" unless functions.is_a?(Hash)

      functions.each do |name, callable|
        raise ArgumentError, "a function's name is a String, not #{name.inspect}" unless name.is_a?(String)
        raise ArgumentError, "the function #{name} does not respond to call" unless callable.respond_to?(:call)
      end
    end
    private_class_method :check_functions

    # The error values the loop and every opcode's handler refuse with when
    # the stack or the instruction itself is wrong. {Machine} includes it.
    module Refusals
      private

      def insufficient(opcode)
        EvaluationError.new(reason: "insufficient_operands",
                            message: "#{opcode} needs more operands than the stack holds")
      end

      def unknown(at)
        EvaluationError.new(reason: "unknown_instruction", message: "Unknown instruction at index #{at}")
      end

      def retired(opcode, version)
        EvaluationError.new(reason: "retired_opcode",
                            message: "#{opcode} was retired at instruction-set version #{version}")
      end
    end
    private_constant :Refusals

    # One evaluation: the program, the context (which a `store` replaces),
    # the policy, the clock, the host's functions, the loop budget left, the
    # stack, the first root a load did not find bound and the value the last
    # `pop` discarded. Each handler answers the index of the next
    # instruction, or the error value that stops the run. The handlers of
    # the arithmetic opcodes are in {Arithmetic}, those of access,
    # membership and list construction in {Access}, those of durations,
    # relative dates and maps in {RichTypes}, that of `call` in {Calls},
    # which includes the library {Library} defines, and those of the
    # statement and jump opcodes in {Statements}, and that of `cast` in
    # {Casts}; Machine includes all six, and the refusals they share in
    # {Refusals}.
    class Machine
      include Refusals
      include Arithmetic
      include Access
      include RichTypes
      include Calls
      include Statements
      include Casts

      def initialize(program, context, settings)
        @program = program
        @context = context
        @on_unbound = settings.on_unbound
        @clock = settings.clock
        @functions = settings.functions
        @budget = settings.loop_budget
        @stack = []
        @unbound = nil
        @last_value = UNDEFINED
      end

      # Runs in expression mode: the answer is the top of the stack at halt.
      def run = drive&.then { |error| Results.failure(error) } || halt

      # Runs in statement mode: the answer is the context at halt. Neither
      # halt rule of expression mode applies, as there is no stack value to
      # answer.
      def run_statements = StatementResult.new(error: drive, context: @context, value: @last_value)

      private

      # Runs the program until it halts, answering the error that stopped it,
      # or nil when it halted.
      def drive
        at = 0
        while at < @program.size
          step = step(@program[at], at)
          return step unless step.is_a?(Integer)

          at = step
        end
        nil
      rescue ClockFault => e
        e.error
      end

      # The answer at halt. An empty stack is an error; undefined on top is
      # an unbound-variable error naming the first root a load did not find,
      # when a load did not find one.
      def halt
        return Results.failure(EvaluationError.new(reason: "empty_stack", message: "the stack is empty at halt")) \
          if @stack.empty?
        return Results.failure(unbound(@unbound)) if UNDEFINED.equal?(@stack.last) && @unbound

        Results.ok(@stack.last)
      end

      # A retired opcode is refused by its name whatever its operands, as the
      # reference refuses it; any other instruction's shape is checked, and
      # only then does it run.
      def step(instruction, at)
        named = INSTRUCTIONS[instruction.first] if instruction.is_a?(Array)
        return retired(instruction.first, named.removed_in) if named&.retired?

        row = row_for(instruction)
        return unknown(at) unless row

        send(row.handler, at, *instruction.drop(1))
      end

      def row_for(instruction)
        return unless instruction.is_a?(Array)

        row = INSTRUCTIONS[instruction.first]
        return unless row && instruction.size == row.operands.size + 1

        row if row.operands.each_with_index.all? { |shape, index| SHAPES.fetch(shape).call(instruction[index + 1]) }
      end

      def push(at, value)
        @stack.push(value)
        at + 1
      end

      # A root the context binds is read as it is, null and undefined
      # included; one it does not bind is undefined, recorded for the halt
      # rule, or under the :error policy an error at once.
      def load_root(at, name)
        return push(at, @context[name]) if @context.key?(name)
        return unbound(name) if @on_unbound == :error

        @unbound ||= name
        push(at, UNDEFINED)
      end

      def compare(at, operator)
        return insufficient("compare") if @stack.size < 2

        right = @stack.pop
        left = @stack.pop
        push(at, Compare.call(operator, left, right))
      end

      def logical_not(at) = negate(at, "logical_not")
      def unary_bang(at) = negate(at, "unary_bang")

      def negate(at, operation)
        return insufficient(operation) if @stack.empty?

        operand = @stack.pop
        return mismatch(operation, "a boolean", operand) unless true.equal?(operand) || false.equal?(operand)

        push(at, !operand)
      end

      def unary_minus(at)
        return insufficient("unary_minus") if @stack.empty?

        operand = @stack.pop
        return mismatch("unary_minus", "a number", operand) unless operand.is_a?(Integer) || operand.is_a?(Float)

        push(at, -operand)
      end

      def jump_if_falsy_or_pop(at, offset) = conditional_jump(at, offset, "jump_if_falsy_or_pop", false)
      def jump_if_true_or_pop(at, offset) = conditional_jump(at, offset, "jump_if_true_or_pop", true)

      # Jumps when the top's truth is jump_on, leaving it on the stack as the
      # answer; otherwise pops it and falls through. False, null and
      # undefined are falsy, exactly true is true, and anything else is a
      # type mismatch.
      def conditional_jump(at, offset, opcode, jump_on)
        return insufficient(opcode) if @stack.empty?

        truth = truth(@stack.last)
        return mismatch(opcode, "a boolean", @stack.last) if truth.nil?
        return at + offset if truth == jump_on

        @stack.pop
        at + 1
      end

      def truth(value)
        return true if true.equal?(value)

        false if false.equal?(value) || value.nil? || UNDEFINED.equal?(value)
      end

      # A refused operand. When it is the undefined an unbound load pushed,
      # the run reports the unbound variable instead, as the reference does.
      def mismatch(operation, wanted, operand)
        return unbound(@unbound) if UNDEFINED.equal?(operand) && @unbound

        TypeMismatchError.new(reason: operation, message: "#{operation} expects #{wanted}")
      end

      def unbound(name) = UndefinedVariableError.new(reason: "unbound_variable", message: "Undefined variable: #{name}")
    end
  end
  private_constant :Evaluator
end

require_relative "evaluator/compare"
require_relative "evaluator/order"
