# frozen_string_literal: true

require "test_helper"
require_relative "parser_helper"

# Programs: statement sequences, assignments, `if`, `else if` and `while`,
# and their positions and spans.
class ParserStatementsTest < Minitest::Test
  include ParserHelper

  # sabotage: keep reading after a statement only on a separator (answer
  # false where no separator is in Statements#continues?); `if a { } b =
  # 1` is refused and the assert_trees flunks.
  def test_a_program_reads_statements_separated_by_semicolons_or_after_a_closing_brace
    assert_trees({
                   "a = 1; b.c[d] = a;" => [[:assignment, id("a"), lit(1)],
                                            [:assignment, [:bracket_access, [:property_access, id("b"), "c"], id("d")],
                                             id("a")]],
                   "if a { } b = 1" => [[:if, id("a"), [:block, []], nil], [:assignment, id("b"), lit(1)]],
                   "while x < 3 { x = x + 1; }" => [[:while, [:comparison, :lt, id("x"), lit(3)],
                                                     [:block, [[:assignment, id("x"),
                                                                [:arithmetic, :add, id("x"), lit(1)]]]]]],
                   "(a) = 1" => [[:assignment, id("a"), lit(1)]], "1" => [lit(1)]
                 }, program: true)
  end

  # sabotage: read `else if` as an else block of its own (answer `block`
  # whatever follows `else` in Statements#else_clause); `else if` is
  # refused and the assert_trees flunks.
  def test_an_else_if_is_an_else_block_holding_one_if
    assert_trees({
                   "if a { b } else if c { d } else { e }" =>
                     [[:if, id("a"), [:block, [id("b")]],
                       [:block, [[:if, id("c"), [:block, [id("d")]], [:block, [id("e")]]]]]]]
                 }, program: true)
  end

  # sabotage: position an else-if block at its condition
  # (`nested.condition.position` for `nested.position` in
  # Statements#else_clause); the else block's position differs and the
  # assert_located fails.
  def test_an_else_if_block_borrows_the_position_and_span_of_its_if
    assert_located("if a { b } else if c { d }",
                   { [:statements, 0, :else_block] => [[1, 17], [1, 17], [1, 27]],
                     [:statements, 0, :else_block, :statements, 0] => [[1, 17], [1, 17], [1, 27]] }, program: true)
  end

  # sabotage: span a program to its last token (end_of(previous) for the
  # last statement's end in Descent#whole_program); the trailing
  # separator is spanned and the assert_located fails.
  def test_statements_are_positioned_as_the_reference_positions_them
    assert_located("x = 1;\nif a { y }  ;",
                   { [] => [[1, 1], [1, 1], [2, 11]], [:statements, 0] => [[1, 3], [1, 1], [1, 6]],
                     [:statements, 1] => [[2, 1], [2, 1], [2, 11]],
                     [:statements, 1, :then_block] => [[2, 6], [2, 6], [2, 11]] }, program: true)
  end

  # sabotage: read a statement that starts with `else` as an expression
  # (drop `else_kw: :stray_else` from Statements::KEYWORDS); the second
  # `else` is refused as a statement keyword and the assert_refusals
  # fails.
  def test_a_second_else_and_an_assignment_in_a_condition_are_refused
    assert_refusals({
                      "if a { } else { } else { }" => ["unexpected_else", "Unexpected 'else' - an 'else' block " \
                                                                          "must follow an 'if' block.",
                                                       [1, 19], [1, 19], [1, 23]],
                      "a.b() = 1" => ["unassignable_location", "Left side of '=' must be an assignable location - " \
                                                               "an identifier, a property access, or a bracket access.",
                                      [1, 7], [1, 7], [1, 8]]
                    }, program: true)
  end
end
