# frozen_string_literal: true

require "test_helper"
require_relative "evaluator_helper"

# store and pop, beyond what the corpus's cases pin: the write algorithm,
# its refusals, and that the caller's context is never changed.
class EvaluatorStatementsTest < Minitest::Test
  include EvaluatorHelper

  # Writes a path cannot take: the reason, the path and the context.
  REFUSED_WRITES = [
    ["not_a_container", %w[a b], { "a" => 1 }],
    ["not_a_container", %w[a b c], { "a" => { "b" => "s" } }],
    ["not_a_container", %w[d x], { "d" => Predicator::Date.new(year: 2001, month: 2, day: 3) }],
    ["not_a_container", %w[xs k], { "xs" => [] }],
    ["not_a_container", ["xs", "k", 0], { "xs" => [] }],
    ["invalid_index", ["xs", -1], { "xs" => [1] }],
    ["invalid_index", ["xs", -1, 0], { "xs" => [1] }]
  ].freeze

  def written(instructions, context = {})
    result = EVALUATOR.execute(instructions, context)
    assert_predicate result, :ok?, -> { "failed with #{result.error.inspect}" }
    result.context
  end

  def store(path, value) = path.map { |segment| ["lit", segment] } + [["lit", value], ["store", path.size]]

  # sabotage: make Location.vivify answer `{}` for every absent slot; xs
  # becomes a map and the first assert_equal fails.
  def test_store_vivifies_a_list_before_an_index_and_a_map_before_a_key
    assert_equal({ "xs" => [Predicator::UNDEFINED, Predicator::UNDEFINED, 9] }, written(store(["xs", 2], 9)))
    assert_equal({ "a" => { "b" => [{ "c" => 1 }] } }, written(store(["a", "b", 0, "c"], 1)))
    assert_equal({ "a" => { "b" => 1 } }, written(store(%w[a b], 1), { "a" => nil }))
    assert_equal({ "a" => { "b" => 1 } }, written(store(%w[a b], 1), { "a" => Predicator::UNDEFINED }))
  end

  # sabotage: drop the `list.fill(...)` line from Location.set; the gap is
  # padded with null and the assert_equal on the padded list fails.
  def test_store_pads_a_list_with_undefined_and_overwrites_a_leaf
    assert_equal({ "xs" => [1, Predicator::UNDEFINED, 3] }, written(store(["xs", 2], 3), { "xs" => [1] }))
    assert_equal({ "xs" => [7, 2] }, written(store(["xs", 0], 7), { "xs" => [1, 2] }))
    assert_equal({ "m" => { "k" => [1] } }, written(store(%w[m k], [1]), { "m" => { "k" => { "deep" => 1 } } }))
  end

  # sabotage: make Location.set answer `container.merge!(segment => value)`;
  # the caller's map is changed and the assert_equal on context fails.
  def test_store_never_changes_the_context_the_caller_passed
    inner = { "b" => 1, "c" => [1, 2] }
    context = { "a" => inner, "x" => 0 }
    snapshot = Marshal.load(Marshal.dump(context))

    assert_equal({ "a" => { "b" => 2, "c" => [1, 5] }, "x" => 0 },
                 written(store(%w[a b], 2) + store(["a", "c", 1], 5), context))
    assert_equal snapshot, context
    assert_same inner, context["a"]
  end

  # sabotage: make Location.vivify answer `slot` for a Duration; the write
  # into a duration is refused and written's assert_predicate fails.
  def test_store_writes_through_a_duration_as_the_map_of_its_units
    units = %w[years months weeks days hours minutes seconds milliseconds].to_h { |unit| [unit, 0] }

    assert_equal({ "d" => units.merge("days" => 5) },
                 written(store(%w[d days], 5), { "d" => Predicator::Duration.new(days: 2) }))
  end

  # sabotage: make the segment check in Statements#store accept anything;
  # the Integer key is still written and the null key's assert_fails's
  # refute_predicate fails.
  def test_store_takes_string_and_integer_segments_only
    assert_equal({ 0 => 1 }, written(store([0], 1)))
    assert_equal({ "m" => { 3 => 9 } }, written(store(["m", 3], 9), { "m" => {} }))
    [nil, true, 1.5, [1], {}].each do |segment|
      assert_fails "TypeMismatchError", "store", store(["a", segment], 1) + [["lit", 1]]
    end
  end

  # sabotage: drop the unbound rewrite from Machine#mismatch (its `return
  # unbound(@unbound) if ...` line); the segment is a TypeMismatchError and
  # assert_fails's assert_equal fails.
  def test_an_unbound_segment_is_reported_as_the_unbound_variable
    assert_fails "UndefinedVariableError", "unbound_variable",
                 [%w[lit a], %w[load nope], ["lit", 1], ["store", 2], ["lit", 1]]
  end

  # sabotage: drop the `path.empty?` refusal from Location.put; ["store", 0]
  # writes the value under a nil key, the run answers 1, and assert_fails's
  # refute_predicate fails.
  def test_store_refuses_an_empty_path
    assert_fails "EvaluationError", "not_assignable", [["lit", 1], ["store", 0], ["lit", 1]]
  end

  # sabotage: make Location.vivify answer `{}` for a slot of any other
  # kind; the scalar is overwritten and the first assert_fails's
  # refute_predicate fails.
  def test_store_refuses_a_scalar_slot_a_key_into_a_list_and_a_negative_index
    REFUSED_WRITES.each do |reason, path, context|
      assert_fails "EvaluationError", reason, store(path, 1) + [["lit", 1]], context
    end
  end

  # sabotage: make the depth check in Statements#store `< count`; one value
  # for ["store", 1] goes on and assert_fails's assert_equal fails.
  def test_store_and_pop_refuse_too_few_operands
    assert_fails "EvaluationError", "insufficient_operands", [%w[lit x], ["store", 1]]
    assert_fails "EvaluationError", "insufficient_operands", [["store", 0]]
    assert_fails "EvaluationError", "insufficient_operands", [["pop"]]
  end

  # sabotage: make Statements#discard leave the top on the stack; the run
  # answers 1 and assert_fails's refute_predicate fails.
  def test_pop_discards_the_top_and_an_empty_stack_at_halt_stays_an_error_in_expression_mode
    assert_answers 1, [["lit", 1], ["lit", 2], ["pop"]]
    assert_fails "EvaluationError", "empty_stack", [["lit", 1], ["pop"]]
  end

  # sabotage: answer `value: UNDEFINED` in Machine#run_statements; the
  # assert_equal on [result.context, result.value] fails.
  def test_statement_mode_answers_the_context_and_the_last_popped_value
    program = [["lit", 1], ["pop"], ["lit", 2], ["pop"]] + store(["x"], 3)
    result = EVALUATOR.execute(program, { "y" => 0 })

    assert_predicate result, :ok?
    assert_equal [{ "y" => 0, "x" => 3 }, 2], [result.context, result.value]
    assert_same Predicator::UNDEFINED,
                EVALUATOR.execute(store(["x"], 3) + [["lit", true], ["pop_jump_if_falsy", 1]]).value
    assert_equal({}, EVALUATOR.execute([["lit", 1], ["lit", 2]]).context)
  end

  # sabotage: answer `context: {}` in Machine#run_statements; the partial
  # context loses x and the assert_equal on result.context fails.
  def test_a_statement_run_that_stops_keeps_every_write_made_before_it
    context = { "a" => 1 }
    result = EVALUATOR.execute(store(["x"], 1) + store(%w[a b], 2) + store(["z"], 3), context)

    refute_predicate result, :ok?
    assert_equal %w[EvaluationError not_a_container], [result.error.type, result.error.reason]
    assert_equal({ "a" => 1, "x" => 1 }, result.context)
    assert_equal({ "a" => 1 }, context)
  end

  # sabotage: drop `@context = written` from Statements#store; the load
  # reads the context's 1 and the first assert_answers's assert_same fails.
  def test_a_store_is_read_back_by_a_later_load
    assert_answers 2, store(["x"], 2) + [%w[load x]], { "x" => 1 }
    assert_answers 1, [%w[load nope], ["pop"]] + store(["nope"], 1) + [%w[load nope]]
  end
end
