# frozen_string_literal: true

require "test_helper"
require_relative "parser_helper"

# How a refusal names a token, and the tokens the lexer never hands the
# parser where it would read them, refused rather than read.
class ParserTokensTest < Minitest::Test
  include ParserHelper

  TOKEN = LEXER.const_get(:Token)
  FRACTION = LEXER.const_get(:Fraction)
  EOF = TOKEN.new(type: :eof, line: 1, column: 5, length: 0)

  Primaries = PARSER.const_get(:Primaries)

  KEY = "Expected identifier or string for object key but found "

  # sabotage: name a float by Ruby's spelling (`value.to_s` for
  # FloatText.spell in TokenText#spelling); 1.0e20 is named 1.0e+20 and
  # the assert_equal fails.
  def test_a_refusal_names_the_token_as_the_reference_names_it
    keys = ["100000000000000000000.0", "1.5", "#{"9" * 400}.5", "#2024-01-15#", "#2024-01-15T10:00:00.5Z#", "f()",
            "and", "'k' 'v'"]

    assert_equal(["#{KEY}number '1.0e20'", "#{KEY}number '1.5'", "#{KEY}number 'Infinity'",
                  "#{KEY}date '2024-01-15'", "#{KEY}datetime '2024-01-15T10:00:00.500000Z'", "#{KEY}function 'f'",
                  "#{KEY}'AND'", "Expected ':' after object key but found string \"v\""],
                 keys.map { |key| refused("{#{key}: 1}")[1] })
  end

  def refusal_message(*tokens) = PARSER.parse([*tokens, EOF]).error.message

  # sabotage: read a function name with no parenthesis after it as a call
  # (drop the expect of :lparen in Primaries#call); the expect of :rparen
  # names the end of input instead and the assert_equal fails.
  def test_a_function_name_with_no_parenthesis_after_it_is_not_a_primary
    name = TOKEN.new(type: :function_name, line: 1, column: 1, length: 1, value: "f")
    argument = TOKEN.new(type: :identifier, line: 1, column: 3, length: 1, value: "x")

    assert_equal "#{Primaries::EXPECTED} identifier 'x'", refusal_message(name, argument)
  end

  # sabotage: read a number with a point and no unit after it as a
  # literal (`literal(token)` for `not_a_primary(token)` in
  # Primaries#fraction); the stream parses and the assert_kind_of fails.
  def test_a_number_with_a_point_and_no_unit_after_it_is_not_a_primary_and_a_unit_alone_is_named
    fraction = TOKEN.new(type: :fractional_number, line: 1, column: 1, length: 3,
                         value: FRACTION.new(whole: 1, fraction: "5"))

    assert_kind_of REFUSAL, PARSER.parse([fraction, EOF])
    assert_equal "#{Primaries::EXPECTED} number '1.5'", refusal_message(fraction)
    assert_equal "#{Primaries::EXPECTED} duration unit 'd'",
                 refusal_message(TOKEN.new(type: :duration_unit, line: 1, column: 1, length: 1, value: "d"))
  end

  # sabotage: let the cast names drift (drop "duration" from
  # Parser::CAST_TYPE_NAMES); the assert_equal fails.
  def test_a_cast_names_one_of_the_evaluator_type_names
    assert_equal Predicator.const_get(:Evaluator).const_get(:Casts)::TYPE_NAMES, PARSER::CAST_TYPE_NAMES
  end
end
