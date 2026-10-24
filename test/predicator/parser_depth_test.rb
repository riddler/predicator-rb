# frozen_string_literal: true

require "test_helper"
require_relative "parser_helper"

# The nesting-depth bound: how deep a source may nest before the parser
# refuses it, what counts as a level and what does not, and the refusal on
# a stack too small to reach the bound.
class ParserDepthTest < Minitest::Test
  include ParserHelper

  LIMIT = PARSER::DEPTH_LIMIT

  # One level past the limit, each written with one kind of nesting: the
  # opener, the innermost source, the closer, how many openers, and the
  # column of the token the descent stops on.
  DEEPER = [["(", "x", ")", LIMIT, LIMIT + 1], ["x[", "1", "]", LIMIT, (2 * LIMIT) + 1],
            ["!", "x", "", LIMIT, LIMIT + 1], ["-(", "x", ")", LIMIT / 2, LIMIT + 1]].freeze

  def nested(open, inner, close, levels) = (open * levels) + inner + (close * levels)

  def too_deep(column)
    ["nesting_depth_exceeded", "Expression nests past the depth limit of #{LIMIT} levels, the whole expression " \
                               "counting as the first", [1, column], [1, column], [1, column + 1]]
  end

  # sabotage: refuse one level early (`@depth < DEPTH_LIMIT` for
  # `@depth <= DEPTH_LIMIT` in Descent#enter); the source at exactly the
  # limit is refused and the first assert_equal flunks.
  def test_a_source_at_the_limit_parses_and_one_level_deeper_is_refused_where_the_descent_stopped
    assert_equal :identifier, tree(nested("(", "x", ")", LIMIT - 1)).first
    assert_refusals(DEEPER.to_h do |open, inner, close, levels, column|
      [nested(open, inner, close, levels), too_deep(column)]
    end)
  end

  # sabotage: count a level for each operator of a chain and never give
  # it back (call `enter` after `token = advance` in Operators#chain); the
  # long chain is refused and the first assert_equal flunks.
  def test_a_chain_of_operators_or_postfix_steps_costs_no_depth
    assert_equal :logical_or, tree((["a"] * (LIMIT * 4)).join(" or ")).first
    assert_equal :arithmetic, tree((["a"] * (LIMIT * 4)).join(" - ")).first
    assert_equal :property_access, tree("a#{".b" * (LIMIT * 4)}").first
  end

  # sabotage: leave the count up when a production is refused (move
  # `@depth -= 1` out of the ensure in Descent#descend, after the
  # yield); each discarded assignment probe leaves a level behind and
  # the program is refused, so the first assert_equal flunks.
  def test_a_discarded_probe_leaves_no_level_behind
    assert_equal :logical_not, statements((["NOT (a)"] * (LIMIT * 2)).join("; ")).last.first
  end

  # sabotage: let a SystemStackError through (drop the rescue in
  # Descent#guarded); the Fiber answers the error, which destructures
  # to nil fields, and the first assert_equal fails.
  def test_a_stack_too_small_for_the_limit_is_refused_rather_than_raising
    source = nested("(", "x", ")", LIMIT - 1)
    reason, message, position = on_a_fiber { refused(source) }

    assert_equal ["nesting_depth_exceeded", "Expression nests deeper than the stack this parse runs on can " \
                                            "follow, short of the depth limit of #{LIMIT} levels"], [reason, message]
    assert_operator position.last, :<, LIMIT
    assert_equal :identifier, tree(source).first
  end

  # What the block answers on a new Fiber, whose default stack is smaller
  # than a thread's; a SystemStackError is answered rather than raised.
  def on_a_fiber
    Fiber.new do
      yield
    rescue SystemStackError => e
      e
    end.resume
  end
end
