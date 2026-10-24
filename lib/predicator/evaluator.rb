# frozen_string_literal: true

require_relative "values"
require_relative "errors"
require_relative "result"

module Predicator
  # The stack machine that runs an instruction list against a context, in
  # expression mode: the answer is the top of the stack at halt. It is
  # private to the package until the public entry points call it.
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
  # evaluation builds its own Machine.
  module Evaluator
    # The instruction-set version this build runs: an opcode retired at or
    # below it is refused.
    ISA_VERSION = 6

    # What a load of a root the context does not bind does: :undefined
    # pushes undefined (and the answer is an unbound-variable error if
    # undefined is what the program answers); :error stops at the load.
    UNBOUND_POLICIES = %i[undefined error].freeze

    # One instruction's row: the shape of each operand, the version that
    # retired it (nil while it is live) and the Machine method that runs it.
    Row = Data.define(:operands, :removed_in, :handler)

    # Each operand shape, as a test of one operand.
    SHAPES = {
      value: ->(_operand) { true },
      string: ->(operand) { operand.is_a?(String) },
      comparison_operator: ->(operand) { Compare::OPERATORS.include?(operand) },
      positive_integer: ->(operand) { operand.is_a?(Integer) && operand.positive? }
    }.freeze

    # The instructions this build knows, by opcode. `and` and `or` were
    # retired at instruction-set version 3; they keep their rows so that a
    # list carrying them is refused as retired rather than as unknown.
    INSTRUCTIONS = {
      "lit" => Row.new(operands: [:value], removed_in: nil, handler: :push_literal),
      "load" => Row.new(operands: [:string], removed_in: nil, handler: :load_root),
      "compare" => Row.new(operands: [:comparison_operator], removed_in: nil, handler: :compare),
      "not" => Row.new(operands: [], removed_in: nil, handler: :logical_not),
      "unary_bang" => Row.new(operands: [], removed_in: nil, handler: :unary_bang),
      "unary_minus" => Row.new(operands: [], removed_in: nil, handler: :unary_minus),
      "jump_if_falsy_or_pop" => Row.new(operands: [:positive_integer], removed_in: nil,
                                        handler: :jump_if_falsy_or_pop),
      "jump_if_true_or_pop" => Row.new(operands: [:positive_integer], removed_in: nil,
                                       handler: :jump_if_true_or_pop),
      "and" => Row.new(operands: [], removed_in: 3, handler: nil),
      "or" => Row.new(operands: [], removed_in: 3, handler: nil)
    }.freeze

    # Runs instructions against context in expression mode.
    #
    # @param instructions [Array] the instruction list
    # @param context [Hash{String => Object}] the variables a load reads
    # @param on_unbound [Symbol] one of {UNBOUND_POLICIES}
    # @return [Result] the top of the stack at halt, or the error that
    #   stopped the run
    # @raise [ArgumentError] when an argument is not of its kind (a caller's
    #   bug, not an outcome of the program)
    def self.evaluate(instructions, context = {}, on_unbound: :undefined)
      raise ArgumentError, "instructions must be an Array, not #{instructions.inspect}" unless instructions.is_a?(Array)
      raise ArgumentError, "context must be a Hash, not #{context.inspect}" unless context.is_a?(Hash)
      unless UNBOUND_POLICIES.include?(on_unbound)
        raise ArgumentError, "on_unbound must be one of #{UNBOUND_POLICIES.inspect}, not #{on_unbound.inspect}"
      end

      Machine.new(instructions, context, on_unbound).run
    end

    # One evaluation: the program, the context, the policy, the stack and the
    # first root a load did not find bound. Each handler answers the index
    # of the next instruction, or the error value that stops the run.
    class Machine
      def initialize(program, context, on_unbound)
        @program = program
        @context = context
        @on_unbound = on_unbound
        @stack = []
        @unbound = nil
      end

      def run
        at = 0
        while at < @program.size
          step = step(@program[at], at)
          return Result.failure(step) unless step.is_a?(Integer)

          at = step
        end
        halt
      end

      private

      # The answer at halt. An empty stack is an error; undefined on top is
      # an unbound-variable error naming the first root a load did not find,
      # when a load did not find one.
      def halt
        return Result.failure(EvaluationError.new(reason: "empty_stack", message: "the stack is empty at halt")) \
          if @stack.empty?
        return Result.failure(unbound(@unbound)) if UNDEFINED.equal?(@stack.last) && @unbound

        Result.ok(@stack.last)
      end

      # The instruction's shape is checked first, then whether it is
      # retired, and only then does it run.
      def step(instruction, at)
        row = row_for(instruction)
        return unknown(at) unless row
        return retired(instruction.first, row.removed_in) if retired?(row)

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

      def push_literal(at, value) = push(at, value)

      def retired?(row) = !row.removed_in.nil? && row.removed_in <= ISA_VERSION

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
        return mismatch(operation, "boolean", operand) unless true.equal?(operand) || false.equal?(operand)

        push(at, !operand)
      end

      def unary_minus(at)
        return insufficient("unary_minus") if @stack.empty?

        operand = @stack.pop
        return mismatch("unary_minus", "number", operand) unless operand.is_a?(Integer) || operand.is_a?(Float)

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
        return mismatch(opcode, "boolean", @stack.last) if truth.nil?
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

        TypeMismatchError.new(reason: operation, message: "#{operation} expects a #{wanted}")
      end

      def unbound(name) = UndefinedVariableError.new(reason: "unbound_variable", message: "Undefined variable: #{name}")

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
  end
  private_constant :Evaluator
end

require_relative "evaluator/compare"
require_relative "evaluator/order"
