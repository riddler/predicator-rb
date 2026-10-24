# frozen_string_literal: true

require "test_helper"

# Predicator.compile and Predicator.compile_program: a source in, a result
# out, carrying the instruction list or the first refusal.
class CompileTest < Minitest::Test
  def compiled(source) = Predicator.compile(source).value
  def program(source) = Predicator.compile_program(source).value

  def refused(result)
    refute_predicate result, :ok?
    error = result.error
    [error.type, error.reason, error.position.line, error.position.column]
  end

  # sabotage: compile an expression as a program (make Predicator.compile
  # pass `program: true` and parse with Parser.parse_program); `x > 1`
  # emits a trailing pop and the first assert_equal fails.
  def test_compile_answers_an_expression_instruction_list_with_its_operands_as_values
    assert_equal [%w[load x], ["lit", 1], %w[compare GT]], compiled("x > 1")
    assert_equal [["lit", Predicator::Date.new(2026, 1, 2)], ["lit", 1.0], %w[compare EQ]],
                 compiled("#2026-01-02# == 1.0")
    assert_equal [["duration", [[3, "d"], [8, "h"]]], %w[relative_date ago]], compiled("3d8h ago")
  end

  # sabotage: drop the else-block branch of Statements#if_statement (always emit
  # the if-without-else shape); the else program's jumps differ and the
  # assert_equal fails.
  def test_compile_program_answers_a_statement_instruction_list
    assert_equal [%w[lit x], ["lit", 1], ["store", 1], %w[load x], ["pop"]], program("x = 1; x")
    assert_equal [%w[load c], ["pop_jump_if_falsy", 5], %w[lit y], ["lit", 1], ["store", 1], ["jump", 4],
                  %w[lit y], ["lit", 2], ["store", 1]], program("if c { y = 1 } else { y = 2 }")
    assert_equal [%w[load c], ["pop_jump_if_falsy", 3], %w[load y], ["pop"]], program("if c { y }")
  end

  # sabotage: answer Results.ok(nil) for a refusal in Predicator.compiled;
  # the lexer's refusal is answered as a success and refute_predicate
  # fails.
  def test_each_stage_refusal_is_a_failed_result_carrying_a_parse_error
    assert_equal ["ParseError", "unexpected_character", 1, 3], refused(Predicator.compile("x & y"))
    assert_equal ["ParseError", "assignment_in_expression", 1, 3], refused(Predicator.compile("x = 1"))
    assert_equal ["ParseError", "number_out_of_range", 1, 5], refused(Predicator.compile_program("x = #{"9" * 400}.0"))
  end

  # sabotage: hand out the table's own array (drop the `.dup` in
  # Chains#step); both answers hold the one frozen array and the
  # refute_same fails.
  def test_each_answer_is_its_own_list
    first = Predicator.compile("x > 1").value.last

    refute_same first, Predicator.compile("y > 2").value.last
    refute_predicate first, :frozen?
  end

  # sabotage: drop the String check in Predicator.text_of; an Integer
  # reaches the lexer, which raises NoMethodError, and assert_raises fails.
  def test_a_source_must_be_text
    assert_raises(ArgumentError) { Predicator.compile(1) }
    assert_raises(ArgumentError) { Predicator.compile_program(nil) }
    assert_raises(ArgumentError) { Predicator.compile("x \xFF") }
    assert_raises(ArgumentError) { Predicator.compile((+"\xFF").force_encoding(Encoding::Shift_JIS)) }
  end

  # sabotage: read every source as UTF-8 bytes (force_encoding for any
  # encoding in Predicator.text_of); the UTF-16 source scans as an
  # unexpected character and the first assert_equal fails.
  def test_text_in_another_encoding_is_read_as_the_text_it_is
    assert_equal [%w[load x]], compiled("x".encode(Encoding::UTF_16LE))
    assert_equal [%w[lit é]], compiled("'é'".encode(Encoding::ISO_8859_1))
    assert_equal [%w[load x]], compiled("x".b)
  end
end
