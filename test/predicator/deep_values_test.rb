# frozen_string_literal: true

require "test_helper"

# Values nested deeper than the stack: a program may build one inside its
# loop budget, and equality, ordering and membership answer for it rather
# than overflowing the stack.
class DeepValuesTest < Minitest::Test
  # Builds x and w over [1] and z over [2], each wrapped 9000 times.
  BUILD = "x = [1]; w = [1]; z = [2]; i = 0; while i < 9000 { x = [x]; w = [w]; z = [z]; i = i + 1 }; "

  # What a run answers, or the exception it raised in its place, so that a
  # raise fails an assertion rather than erroring the test.
  def outcome
    yield
  rescue SystemStackError => e
    e
  end

  def bound(program, *names)
    result = outcome { Predicator.execute(BUILD + program) }

    assert_instance_of Predicator::Result, result
    assert_predicate result, :ok?, -> { "failed with #{result.error.inspect}" }
    result.value.values_at(*names)
  end

  # sabotage: make Compare.loose_equal? recurse (replace its queued pairs
  # with `left.zip(right).all? { |a, b| loose_equal?(a, b, by_instant:) }`
  # in peers_equal?); the run overflows the stack and the
  # assert_instance_of in bound fails.
  def test_loose_equality_and_membership_answer_for_values_nested_past_the_stack
    assert_equal [true, false, true], bound("e = x == w; d = x == z; m = z in [x, z]", "e", "d", "m")
  end

  # sabotage: make Compare.strict? recurse (replace the queued pairs in
  # strict_pair? with `left.zip(right).all? { |a, b| strict?(a, b) }`); the
  # run overflows the stack and the assert_instance_of in bound fails.
  def test_strict_equality_answers_for_values_nested_past_the_stack
    assert_equal [true, false], bound("s = x === w; t = x === z", "s", "t")
  end

  # sabotage: hand a member pair of two lists to member_order instead of
  # descending (answer `member_order(*pair)` in Order.frame_step); x < z
  # recurses through Order.order and the assert_instance_of in bound fails.
  def test_ordering_answers_for_values_nested_past_the_stack
    assert_equal [true, false, true], bound("lt = x < z; gt = x > z; le = x <= w", "lt", "gt", "le")
  end

  # sabotage: make Compare.loose_equal? recurse, as for the first test,
  # and drop the identical-container shortcut (`left.equal?(right) ||`) in
  # peers_equal?; the run overflows the stack and the assert_instance_of
  # fails.
  def test_a_program_comparing_a_value_it_nested_9000_levels_deep_answers
    program = "x = []; i = 0; while i < 9000 { x = [x]; i = i + 1 }; y = [x] == [x]"
    result = outcome { Predicator.execute(program) }

    assert_instance_of Predicator::Result, result
    assert_equal true, result.value["y"]
  end
end
