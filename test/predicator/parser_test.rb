# frozen_string_literal: true

require "test_helper"
require_relative "parser_helper"

# The expression trees the parser builds, their positions and spans: the
# reference's precedence and associativity, and its node for each
# construct.
class ParserTest < Minitest::Test
  include ParserHelper

  # sabotage: read the additive level's operands at the unary level
  # (`:unary` for `:multiplication` in Operators#addition); no `*` is
  # read, `a + b * c` is refused and the assert_trees flunks.
  def test_multiplication_binds_tighter_than_addition_and_both_lean_left
    assert_trees({
                   "a + b * c" => [:arithmetic, :add, id("a"), [:arithmetic, :multiply, id("b"), id("c")]],
                   "a - b - c" => [:arithmetic, :subtract, [:arithmetic, :subtract, id("a"), id("b")], id("c")],
                   "a / b % c" => [:arithmetic, :modulo, [:arithmetic, :divide, id("a"), id("b")], id("c")],
                   "(a + b) * c" => [:arithmetic, :multiply, [:arithmetic, :add, id("a"), id("b")], id("c")]
                 })
  end

  # sabotage: read OR's operands at the NOT level (`:logical_not` for
  # `:logical_and` in Operators#logical_or); no `AND` is read, `a OR b
  # AND c` is refused and the assert_trees flunks.
  def test_and_binds_tighter_than_or_and_both_lean_left
    assert_trees({
                   "a OR b AND c" => [:logical_or, id("a"), [:logical_and, id("b"), id("c")]],
                   "a || b or c" => [:logical_or, [:logical_or, id("a"), id("b")], id("c")],
                   "a && b and c" => [:logical_and, [:logical_and, id("a"), id("b")], id("c")]
                 })
  end

  # sabotage: drop :bang from Operators::NEGATIONS; `!a == b` reads its
  # bang at the unary level and the assert_trees fails.
  def test_a_negation_negates_a_whole_comparison_and_a_bang_below_it_an_operand
    assert_trees({
                   "!a == b" => [:logical_not, [:comparison, :equal_equal, id("a"), id("b")]],
                   "NOT not a" => [:logical_not, [:logical_not, id("a")]],
                   "1 + !x" => [:arithmetic, :add, lit(1), [:unary, :bang, id("x")]],
                   "- -5" => [:unary, :minus, [:unary, :minus, lit(5)]],
                   "1 - -2" => [:arithmetic, :subtract, lit(1), [:unary, :minus, lit(2)]]
                 })
  end

  # sabotage: map :strict_equal to :strict_equal in Operators::RELATIONS;
  # `a === b` reads its operator unchanged and the assert_equal fails.
  def test_each_comparison_operator_is_the_reference_operator
    operators = { ">" => :gt, "<" => :lt, ">=" => :gte, "<=" => :lte, "==" => :equal_equal, "!=" => :ne,
                  "===" => :strict_eq, "!==" => :strict_ne }

    assert_equal(operators.transform_values { |operator| [:comparison, operator, id("a"), id("b")] },
                 operators.to_h { |text, _| [text, tree("a #{text} b")] })
  end

  # sabotage: read a membership's right operand at the multiplication
  # level (`multiplication` for the second `addition` in
  # Operators#comparison); `x in a + b` leaves `+ b` over and the
  # assert_trees flunks.
  def test_membership_and_comparison_take_additions_as_operands
    assert_trees({
                   "x IN [1]" => [:membership, :in, id("x"), [:list_literal, [lit(1)]]],
                   "y contains 'z'" => [:membership, :contains, id("y"), str("z")],
                   "x in a + b" => [:membership, :in, id("x"), [:arithmetic, :add, id("a"), id("b")]],
                   "a + 1 > b" => [:comparison, :gt, [:arithmetic, :add, id("a"), lit(1)], id("b")]
                 })
  end

  # sabotage: read a comparison's right operand at the comparison level
  # (`comparison` for the second `addition` in Operators#comparison); a
  # second comparison reads as the right operand and assert_refusals
  # flunks.
  def test_a_comparison_takes_one_operator_so_a_second_is_left_over
    assert_refusals({
                      "a == b == c" => ["trailing_token", "Unexpected token '==' after expression", [1, 8], [1, 8],
                                        [1, 10]],
                      "a in b in c" => ["trailing_token", "Unexpected token 'IN' after expression", [1, 8], [1, 8],
                                        [1, 10]]
                    })
  end

  # sabotage: build every literal with value nil in Primaries#literal; the
  # assert_trees fails.
  def test_a_literal_carries_its_value_and_a_string_its_quote
    day = Predicator::Date.new(year: 2024, month: 1, day: 15)

    assert_trees({ "1" => lit(1), "1.5" => lit(1.5), "true" => lit(true), "false" => lit(false), "null" => lit(nil),
                   "undefined" => lit(Predicator::UNDEFINED), "#2024-01-15#" => lit(day),
                   "#2024-01-15T10:00:00Z#" => lit(Predicator::DateTime.at(day, 10)),
                   '"x"' => str("x", :double), "'x'" => str("x") })
  end

  # sabotage: read an object key's style as :identifier always in
  # Primaries#entry; the quoted keys' styles differ and the assert_trees
  # fails.
  def test_lists_objects_and_calls_keep_their_members_in_order
    assert_trees({
                   %({a: 1, 'b': 2, "c": [x]}) => [:object_literal, [[[:object_key, "a", :identifier], lit(1)],
                                                                     [[:object_key, "b", :single], lit(2)],
                                                                     [[:object_key, "c", :double],
                                                                      [:list_literal, [id("x")]]]]],
                   "[]" => [:list_literal, []], "{}" => [:object_literal, []], "g()" => [:function_call, "g", []],
                   "f(1, math.max(a, b))" => [:function_call, "f", [lit(1), [:function_call, "math.max",
                                                                             [id("a"), id("b")]]]]
                 })
  end

  # sabotage: drop :last_op from Postfix::PROPERTY_NAMES; `a.b[c].last`
  # is refused and the assert_trees flunks.
  def test_postfix_steps_chain_leftward_and_a_relative_date_word_names_a_property
    assert_trees({
                   "a.b[c].last::integer" => [:cast, [:property_access,
                                                      [:bracket_access, [:property_access, id("a"), "b"], id("c")],
                                                      "last"], "integer"],
                   "a.next.ago" => [:property_access, [:property_access, id("a"), "next"], "ago"],
                   "a.from.now" => [:property_access, [:property_access, id("a"), "from"], "now"],
                   "x::duration" => [:cast, id("x"), "duration"],
                   "{integer: date}" => [:object_literal, [[[:object_key, "integer", :identifier], id("date")]]]
                 })
  end

  # sabotage: leave the span alone in Primaries#parenthesized (answer
  # `inner`); the outer parenthesis's span differs and the assert_located
  # fails.
  def test_a_parenthesis_keeps_its_node_and_position_and_widens_its_span
    assert_located("((a + b)) * c", { [] => [[1, 11], [1, 1], [1, 14]], [:left] => [[1, 5], [1, 1], [1, 10]],
                                      %i[left left] => [[1, 3], [1, 3], [1, 4]] })
  end

  # sabotage: point an index at its closing bracket (start_of(close) for
  # start_of(key_token) in Postfix#index); the bracket access's position
  # differs and the first assert_located fails.
  def test_each_node_is_positioned_at_the_token_that_defines_it_and_spans_its_source
    assert_located("-a.b[k]::string", { [] => [[1, 1], [1, 1], [1, 16]], [:operand] => [[1, 10], [1, 2], [1, 16]],
                                        %i[operand expression] => [[1, 6], [1, 2], [1, 8]],
                                        %i[operand expression object] => [[1, 4], [1, 2], [1, 5]] })
    assert_located("f(x,\n 'y') or {k: 1}", { [] => [[2, 7], [1, 1], [2, 16]], [:left] => [[1, 1], [1, 1], [2, 6]],
                                              [:left, :arguments, 1] => [[2, 2], [2, 2], [2, 5]],
                                              [:right, :entries, 0, 0] => [[2, 11], [2, 11], [2, 12]] })
  end
end
