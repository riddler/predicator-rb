# frozen_string_literal: true

module Predicator
  module Evaluator
    # The five arithmetic opcodes, as the reference's ISA (docs/isa.md,
    # section 5) states them: the handlers {Machine} runs for their rows of
    # {INSTRUCTIONS}, and the rule each applies to its pair of operands.
    #
    # Integer and Float stay apart: two Integers answer an Integer, and a
    # Float on either side answers a Float. A Float answer that is not finite
    # (an overflow) has no member in the value domain, and is refused as an
    # EvaluationError with the reason non_finite_number; the reference has no
    # answer there of its own to follow. Integers have no bound.
    #
    # A pair no rule takes is a TypeMismatchError whose reason is the opcode,
    # or the unbound-variable error when an operand is the undefined an
    # unbound load pushed.
    module Arithmetic
      # What a pair no rule takes answers inside this module.
      NO_RULE = Object.new.freeze

      # What each opcode's refusal says it wanted.
      WANTED = {
        "add" => "a number or a string", "subtract" => "a number or a date", "multiply" => "a number",
        "divide" => "a number", "modulo" => "an integer"
      }.freeze

      private

      def add(at) = arithmetic(at, "add") { |left, right| sum(left, right) }
      def subtract(at) = arithmetic(at, "subtract") { |left, right| difference(left, right) }
      def multiply(at) = arithmetic(at, "multiply") { |left, right| numbers?(left, right) ? left * right : NO_RULE }

      # The zero check runs before the type check, for an Integer 0 and a
      # Float 0.0 (negative zero included) alike. Two Integers divide by
      # truncating toward zero.
      def divide(at)
        arithmetic(at, "divide", zero: ->(right) { number?(right) && right.zero? }) do |left, right|
          next NO_RULE unless numbers?(left, right)

          left.is_a?(Integer) && right.is_a?(Integer) ? truncated_quotient(left, right) : left / right
        end
      end

      # Integers only, a Float operand included in the refusal. The zero
      # check runs before the type check for an Integer 0 alone: a Float 0.0
      # is a type mismatch, not modulo by zero. The remainder takes the sign
      # of the dividend.
      def modulo(at)
        arithmetic(at, "modulo", zero: ->(right) { right.is_a?(Integer) && right.zero? }) do |left, right|
          left.is_a?(Integer) && right.is_a?(Integer) ? left.remainder(right) : NO_RULE
        end
      end

      # Pops right then left, refuses a zero divisor when zero says so, and
      # pushes what the rule answers.
      def arithmetic(at, opcode, zero: nil)
        return insufficient(opcode) if @stack.size < 2

        right = @stack.pop
        left = @stack.pop
        return by_zero(opcode) if zero&.call(right)

        answer = yield(left, right)
        return mismatch_pair(opcode, WANTED.fetch(opcode), left, right) if NO_RULE.equal?(answer)
        return non_finite(opcode) if answer.is_a?(Float) && !answer.finite?

        push(at, answer)
      end

      # Numbers add. Strings join, and a number beside a string is written
      # as text first. Lists join. A date or a datetime and a duration, in
      # either order, move the date.
      def sum(left, right)
        return left + right if numbers?(left, right) || both?(left, right, String) || both?(left, right, Array)
        return text(left) + text(right) if text_pair?(left, right)

        shifted(left, right)
      end

      def text_pair?(left, right) = (left.is_a?(String) && number?(right)) || (number?(left) && right.is_a?(String))

      def text(value) = value.is_a?(String) ? value : number_text(value)

      # A date or a datetime moved forward by a duration on either side.
      def shifted(left, right)
        return Chronology.shift(left, right, 1) if Chronology.chronological?(left) && right.is_a?(Duration)
        return Chronology.shift(right, left, 1) if left.is_a?(Duration) && Chronology.chronological?(right)

        NO_RULE
      end

      # Numbers subtract. Two dates or datetimes answer the duration between
      # them, and a date or a datetime minus a duration moves it back. No
      # string or list rule: subtract never joins.
      def difference(left, right)
        return left - right if numbers?(left, right)
        return Chronology.difference(left, right) if Chronology.chronological?(left) && Chronology.chronological?(right)
        return Chronology.shift(left, right, -1) if Chronology.chronological?(left) && right.is_a?(Duration)

        NO_RULE
      end

      def number?(value) = value.is_a?(Integer) || value.is_a?(Float)
      def numbers?(left, right) = number?(left) && number?(right)
      def both?(left, right, type) = left.is_a?(type) && right.is_a?(type)

      def number_text(number) = number.is_a?(Float) ? FloatText.spell(number) : number.to_s

      def truncated_quotient(left, right)
        whole = left.abs / right.abs
        left.negative? == right.negative? ? whole : -whole
      end

      # A refused pair: the operand reported is the undefined one, if either
      # is, so that an unbound load is named.
      def mismatch_pair(opcode, wanted, left, right)
        mismatch(opcode, wanted, UNDEFINED.equal?(right) && !UNDEFINED.equal?(left) ? right : left)
      end

      def by_zero(opcode)
        reason = opcode == "divide" ? "division_by_zero" : "modulo_by_zero"
        EvaluationError.new(reason:, message: "#{opcode} was given a zero divisor")
      end

      def non_finite(opcode)
        EvaluationError.new(reason: "non_finite_number", message: "#{opcode} answered a float that is not finite")
      end
    end
    private_constant :Arithmetic
  end
end
