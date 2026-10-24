# frozen_string_literal: true

require "test_helper"

# The error values: a normative type and reason, a message that is not, and
# a position where the reference gives one; and the exception that carries one.
class ErrorsTest < Minitest::Test
  EVALUATION = [Predicator::EvaluationError, Predicator::TypeMismatchError, Predicator::UndefinedVariableError].freeze

  # sabotage: make ErrorValue#type answer self.class.name; the assert_equal
  # on the corpus's spelling fails.
  def test_each_error_names_its_type_as_the_corpus_spells_it
    assert_equal(%w[EvaluationError TypeMismatchError UndefinedVariableError],
                 EVALUATION.map { |kind| kind.new(reason: "r", message: "m").type })
    at = Predicator::Position.new(1, 3)

    assert_equal "ParseError",
                 Predicator::ParseError.new(reason: "unexpected_character", message: "m", position: at).type
  end

  # sabotage: default position to a Position.new(1, 1) in
  # TypeMismatchError#initialize; the assert_nil fails.
  def test_an_evaluation_error_carries_reason_message_and_an_optional_position
    error = Predicator::TypeMismatchError.new(reason: "add", message: "add wants numbers")
    placed = Predicator::TypeMismatchError.new(reason: "add", message: "add wants numbers",
                                               position: Predicator::Position.new(2, 5))

    assert_equal ["add", "add wants numbers"], [error.reason, error.message]
    assert_nil error.position
    assert_equal Predicator::Position.new(line: 2, column: 5), placed.position
    refute_equal error, placed
  end

  # sabotage: pass position_required: false from ParseError#initialize; the
  # assert_raises on a parse error with no position fails.
  def test_a_parse_error_always_has_a_position
    assert_raises(ArgumentError) { Predicator::ParseError.new(reason: "trailing_token", message: "m", position: nil) }
    assert_raises(ArgumentError) { Predicator::ParseError.new(reason: "trailing_token", message: "m") }
  end

  # sabotage: drop the reason test from ErrorValue#check; the assert_raises
  # on a Symbol reason fails.
  def test_an_error_refuses_fields_of_the_wrong_type
    assert_raises(ArgumentError) { Predicator::EvaluationError.new(reason: :empty_stack, message: "m") }
    assert_raises(ArgumentError) { Predicator::EvaluationError.new(reason: "empty_stack", message: nil) }
    assert_raises(ArgumentError) { Predicator::EvaluationError.new(reason: "r", message: "m", position: [1, 2]) }
  end

  # sabotage: test part >= 0 in Position#initialize; the assert_raises on
  # column 0 fails.
  def test_a_position_counts_from_one
    assert_raises(ArgumentError) { Predicator::Position.new(1, 0) }
    assert_raises(ArgumentError) { Predicator::Position.new(0, 1) }
    assert_raises(ArgumentError) { Predicator::Position.new("1", 1) }
    assert_raises(ArgumentError) { Predicator::Position.new(1, 1.5) }
    assert_equal({ line: 1, column: 1 }, Predicator::Position.new(1, 1).to_h)
  end

  # sabotage: call super with no argument in Predicator::Error#initialize;
  # the assert_equal on the exception's message fails.
  def test_the_exception_carries_the_error_value
    value = Predicator::UndefinedVariableError.new(reason: "unbound_variable", message: "x is not bound")
    raised = assert_raises(Predicator::Error) { raise Predicator::Error, value }

    assert_same value, raised.error
    assert_equal "x is not bound", raised.message
    assert_kind_of StandardError, raised
  end
end
