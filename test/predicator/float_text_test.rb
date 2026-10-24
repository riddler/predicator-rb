# frozen_string_literal: true

require "test_helper"

# How a Float is written into a string: the reference's spelling, checked
# against what the reference writes for the same Floats.
class FloatTextTest < Minitest::Test
  FLOAT_TEXT = Predicator.const_get(:FloatText)

  # Each Float beside the text the reference writes for it.
  SPELLINGS = {
    1.5 => "1.5", 0.1 => "0.1", 100.0 => "100.0", 1230.0 => "1230.0", 12_345.678 => "12345.678",
    999_999.0 => "999999.0", 0.01 => "0.01", 0.0001 => "0.0001", 0.004 => "0.004",
    1000.0 => "1.0e3", 1500.0 => "1.5e3", 12_300.0 => "1.23e4", 3.0e10 => "3.0e10", 1.0e15 => "1.0e15",
    1.0e20 => "1.0e20", 1.0e100 => "1.0e100", 1.0e-5 => "1.0e-5", 0.00015 => "1.5e-4", 2.5e-7 => "2.5e-7",
    123_456_789_012_345_680.0 => "1.2345678901234568e17", 1.7976931348623157e308 => "1.7976931348623157e308",
    5.0e-324 => "5.0e-324", -1500.0 => "-1.5e3", -0.5 => "-0.5", 0.0 => "0.0"
  }.freeze

  # sabotage: change `plain.size <= exponent.size` to `<` in FloatText.spell;
  # 100.0 is written 1.0e2 and the assert_equal on 100.0 fails.
  def test_the_shorter_form_is_written_and_the_plain_one_on_a_tie
    SPELLINGS.each { |float, text| assert_equal text, FLOAT_TEXT.spell(float), float.inspect }
    assert_equal "-0.0", FLOAT_TEXT.spell(-0.0)
  end

  # sabotage: drop the EXPONENT_FROM line from FloatText.spell; 2**53 is
  # written in the plain form and the first assert_equal fails.
  def test_from_two_to_the_fifty_third_the_exponent_form_is_written
    assert_equal "9.007199254740992e15", FLOAT_TEXT.spell(9_007_199_254_740_992.0)
    assert_equal "9007199254740990.0", FLOAT_TEXT.spell(9_007_199_254_740_990.0)
  end
end
