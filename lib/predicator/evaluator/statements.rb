# frozen_string_literal: true

module Predicator
  module Evaluator
    # The statement opcodes and the statement-level jumps, as the reference's
    # ISA (docs/isa.md, section 5) states them: the handlers {Machine} runs
    # for `store`, `pop`, `jump`, `pop_jump_if_falsy` and `jump_backward`.
    #
    # `store` is the one opcode that writes the context. It never changes a
    # map or a list it writes through: each write builds a new context that
    # shares every branch the path does not pass through, so the context the
    # caller passed stays as it was, and a refused write leaves no partial
    # write behind ({Location}).
    #
    # `jump_backward` is the one back edge. Each back edge taken spends one
    # of the evaluation's loop budget; one that finds the budget spent stops
    # the run with loop_budget_exceeded, so a budget of n lets n back edges
    # through. A program with no back edge halts within its length in steps,
    # since every other jump goes forward.
    module Statements
      private

      # Pops the value, then count location segments beneath it, and writes
      # the value into the context at the path those segments name, the
      # deepest-pushed segment first (the root). Too few values is
      # insufficient operands; a segment that is not a String or an Integer
      # is a type mismatch, checked before anything is written; a write the
      # path cannot take is refused as {Location} says. Pushes nothing.
      def store(at, count)
        return insufficient("store") if @stack.size < count + 1

        value = @stack.pop
        path = @stack.pop(count)
        bad = path.index { |segment| !segment.is_a?(String) && !segment.is_a?(Integer) }
        return mismatch("store", "a string or an integer segment", path[bad]) if bad

        written = Location.put(@context, path, value)
        return written if written.is_a?(EvaluationError)

        @context = written
        at + 1
      end

      # `pop`, the statement boundary: discards the stack top, keeping it as
      # the value statement mode answers. An empty stack is insufficient
      # operands; the empty_stack rule belongs to the halt alone.
      def discard(at)
        return insufficient("pop") if @stack.empty?

        @last_value = @stack.pop
        at + 1
      end

      def jump(at, offset) = at + offset

      # Pops the condition whatever it is: false, null and undefined jump,
      # exactly true falls through, and anything else is a type mismatch.
      def pop_jump_if_falsy(at, offset)
        return insufficient("pop_jump_if_falsy") if @stack.empty?

        condition = @stack.pop
        truth = truth(condition)
        return mismatch("pop_jump_if_falsy", "a boolean", condition) if truth.nil?

        truth ? at + 1 : at + offset
      end

      # A target before the first instruction is a malformed operand, an
      # unknown instruction, whatever the budget holds.
      def jump_backward(at, offset)
        return unknown(at) if offset > at
        return loop_budget_exceeded if @budget.zero?

        @budget -= 1
        at - offset
      end

      def loop_budget_exceeded
        EvaluationError.new(reason: "loop_budget_exceeded",
                            message: "the loop budget is spent at a backward jump")
      end
    end
    private_constant :Statements

    # The write `store` makes, as the reference writes a location: each
    # interior slot that is missing, null or undefined becomes a list when
    # the segment after it is an Integer and a map otherwise; a duration is
    # written through as the plain map of its eight units; the leaf is
    # overwritten whatever it holds. A map takes a String or an Integer key.
    # A list takes an index of at least 0, and an index past its end pads the
    # gap with undefined. Every container on the path is copied, never
    # changed.
    #
    # The refusals are EvaluationErrors: not_assignable for an empty path,
    # not_a_container for a slot that holds anything else (a date and an
    # instant included) or a list given a String, and invalid_index for a
    # negative index.
    module Location
      # The context with value written at path, or the EvaluationError that
      # refuses the write.
      def self.put(context, path, value)
        return refusal("not_assignable", "store has no location to write") if path.empty?

        catch(:refused) { write(context, path, value) }
      end

      def self.write(container, path, value)
        segment, *rest = path
        return set(container, segment, value) if rest.empty?

        set(container, segment, write(vivify(fetch(container, segment), rest.first), rest, value))
      end

      def self.fetch(container, segment)
        return container.fetch(segment, nil) if container.is_a?(Hash)

        index!(segment)
        container[segment]
      end

      def self.vivify(slot, following)
        case slot
        when nil, UNDEFINED then following.is_a?(Integer) ? [] : {}
        when Hash, Array then slot
        when Duration then Access.units(slot)
        else throw :refused, refusal("not_a_container", "store cannot write into #{slot.inspect}")
        end
      end

      def self.set(container, segment, value)
        return container.merge(segment => value) if container.is_a?(Hash)

        index!(segment)
        list = container.dup
        list.fill(UNDEFINED, list.size...segment)
        list[segment] = value
        list
      end

      def self.index!(segment)
        throw :refused, refusal("not_a_container", "store cannot write a key into a list") unless segment.is_a?(Integer)
        throw :refused, refusal("invalid_index", "store cannot write at index #{segment}") if segment.negative?
      end

      def self.refusal(reason, message) = EvaluationError.new(reason:, message:)

      private_class_method :write, :fetch, :vivify, :set, :index!, :refusal
    end
    private_constant :Location
  end
end
