# frozen_string_literal: true

module Predicator
  module Evaluator
    # The library's math functions, as the reference's own: each takes
    # numbers (an Integer or a Float) and refuses anything else with the
    # reference's sentence for it.
    #
    # Integers stay exact where the reference keeps them exact: `Math.pow`
    # of two Integers with a non-negative exponent, `Math.sqrt` of an
    # Integer with an exact Integer root, `Math.abs`, `Math.min` and
    # `Math.max` of Integers. `Math.floor`, `Math.ceil` and `Math.round`
    # answer an Integer, rounding half away from zero. Where the reference's
    # float arithmetic has no real, finite answer (`Math.pow(-8, 0.5)`, an
    # overflow), the call is refused rather than answering a complex number
    # or an infinity, which the value domain does not hold.
    module MathFunctions
      private

      def math_pow(base, exponent)
        two_numbers("Math.pow", base, exponent)
        return base**exponent if base.is_a?(Integer) && exponent.is_a?(Integer) && !exponent.negative?

        power = base.to_f**exponent.to_f
        return power if power.is_a?(Float) && power.finite?

        raise Calls::Refusal, "Math.pow has no finite real answer for #{base} and #{exponent}"
      end

      def math_sqrt(value)
        raise Calls::Refusal, "Math.sqrt expects a numeric argument" unless number?(value)
        raise Calls::Refusal, "Math.sqrt expects a non-negative number" if value.negative?

        if value.is_a?(Integer)
          root = Integer.sqrt(value)
          return root if root * root == value
        end
        Math.sqrt(value)
      end

      def math_abs(value) = numeric("Math.abs", value).abs
      def math_floor(value) = numeric("Math.floor", value).to_f.floor
      def math_ceil(value) = numeric("Math.ceil", value).to_f.ceil
      def math_round(value) = numeric("Math.round", value).round

      # The smaller of the two, the first when they are equal.
      def math_min(left, right) = two_numbers("Math.min", left, right) && [left, right].min

      # The larger of the two, the first when they are equal.
      def math_max(left, right) = two_numbers("Math.max", left, right) && [left, right].max

      # A Float from 0.0 up to 1.0, from a generator of its own, so that no
      # state outside this call is read or moved.
      def math_random = Random.new.rand

      def number?(value) = value.is_a?(Integer) || value.is_a?(Float)

      def numeric(name, value)
        return value if number?(value)

        raise Calls::Refusal, "#{name} expects a numeric argument"
      end

      def two_numbers(name, left, right)
        return true if number?(left) && number?(right)

        raise Calls::Refusal, "#{name} expects two numeric arguments"
      end
    end
    private_constant :MathFunctions
  end
end
