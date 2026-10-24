# frozen_string_literal: true

module Predicator
  # How a Float is written as text where predicator writes a number into a
  # string: the reference's own spelling of a float, which is its host
  # language's shortest form. The shortest digits that read back as the same
  # Float are placed in one of two forms:
  #
  # - plain, with a point and a `.0` when the number is whole: `1230.0`,
  #   `0.001`;
  # - exponent, one digit, a point, at least one more digit, `e` and the
  #   exponent, signed only when negative: `1.0e3`, `1.5e-7`.
  #
  # At a magnitude of 2**53 or more the exponent form is written; below it,
  # whichever of the two is shorter, and the plain form when they are the
  # same length. A negative number carries a minus in front of either form;
  # zero is `0.0` and negative zero `-0.0`.
  #
  # It also reads a number's decimal text as the Float nearest it ({read}).
  #
  # The module holds no state. It is private to the package.
  module FloatText
    # The magnitude from which the exponent form is always written.
    EXPONENT_FROM = 2**53

    # The magnitude from which a number rounds to no finite Float: halfway
    # between the largest Float and 2**1024.
    CEILING = (2**1024) - (2**970)

    # The magnitude at or below which a number rounds to a zero Float: half
    # the smallest Float above zero.
    FLOOR = Rational(1, 2**1075)

    module_function

    # The Float nearest the number a decimal text writes (an optional minus,
    # digits, and an optional point and digits; no exponent), or nil when
    # the number is too large for a finite Float. A number too close to zero
    # for any other Float reads as zero, signed as the text is. The
    # magnitude is judged on the exact number first, so the host's parser is
    # never asked for a Float outside its range, where it would print a
    # warning.
    #
    # @param text [String]
    # @return [Float, nil]
    def read(text)
      magnitude = Rational(text).abs
      return if magnitude >= CEILING
      return Float(text.start_with?("-") ? "-0" : "0") if magnitude <= FLOOR

      Float(text)
    end

    # @param value [Float] a finite Float
    # @return [String]
    def spell(value)
      sign = value.to_s.start_with?("-") ? "-" : ""
      return "#{sign}0.0" if value.zero?

      digits, point = shortest_digits(value.abs)
      exponent = exponent_form(digits, point)
      return sign + exponent if value.abs >= EXPONENT_FROM

      plain = plain_form(digits, point)
      sign + (plain.size <= exponent.size ? plain : exponent)
    end

    # The shortest significant digits of a positive Float, without leading or
    # trailing zeros, and where the point falls among them: the Float is
    # 0.DIGITS times ten to the power point. Ruby's own Float#to_s writes the
    # same shortest digits, in a form of its own that this reads apart.
    def shortest_digits(magnitude)
      mantissa, exponent = magnitude.to_s.split("e")
      whole, fraction = mantissa.split(".")
      digits = whole + fraction
      significant = digits.sub(/\A0+/, "")
      point = whole.size + exponent.to_i - (digits.size - significant.size)
      [significant.sub(/0+\z/, ""), point]
    end

    def plain_form(digits, point)
      return "0.#{"0" * -point}#{digits}" if point <= 0
      return "#{digits}#{"0" * (point - digits.size)}.0" if point >= digits.size

      "#{digits[0, point]}.#{digits[point..]}"
    end

    def exponent_form(digits, point)
      fraction = digits.size > 1 ? digits[1..] : "0"
      "#{digits[0]}.#{fraction}e#{point - 1}"
    end
  end
  private_constant :FloatText
end
