# frozen_string_literal: true

require "test_helper"

# The public entry points that run a program, parse a source or read a
# duration, their bang variants, and the options a run takes.
class EntryPointsTest < Minitest::Test
  NOON = CIVIL.instant_at(Predicator::Date.new(2026, 1, 2), 12)

  def described(error) = [error.type, error.reason]

  # sabotage: compile a String with compile_program in Predicator.evaluate;
  # `x > 1` answers no value at halt and the first assert_equal fails.
  def test_evaluate_runs_a_source_or_an_instruction_list
    assert_equal true, Predicator.evaluate("x > 1", { "x" => 2 }).value
    assert_equal 3, Predicator.evaluate([%w[load x], ["lit", 1], ["add"]], { "x" => 2 }).value
    assert_equal %w[ParseError assignment_in_expression], described(Predicator.evaluate("x = 1").error)
    assert_equal %w[EvaluationError division_by_zero], described(Predicator.evaluate("1 / 0").error)
  end

  # sabotage: answer Results.ok(ran.context) whatever ran.ok? says in
  # Predicator.execute; a stopped run answers its partial context and the
  # refute_predicate fails.
  def test_execute_answers_the_context_at_halt_and_never_changes_the_one_passed
    passed = { "x" => 1 }

    assert_equal({ "x" => 1, "y" => 3 }, Predicator.execute("y = x + 2", passed).value)
    assert_equal({ "x" => 1 }, passed)
    stopped = Predicator.execute("a = 1; a.b = 2; c = 3")

    refute_predicate stopped, :ok?
    assert_equal %w[EvaluationError not_a_container], described(stopped.error)
    assert_equal %w[ParseError expected_primary], described(Predicator.execute("x =").error)
  end

  # sabotage: answer Results.ok([ran.value, ran.context]) whatever ran.ok?
  # says in Predicator.execute_value; a stopped run answers a value and the
  # refute_predicate fails.
  def test_execute_value_answers_the_last_expression_value_and_the_context_and_no_value_on_a_stop
    assert_equal [20, { "x" => 2 }], Predicator.execute_value("x = 2; x * 10").value
    assert_equal [Predicator::UNDEFINED, { "x" => 1 }], Predicator.execute_value("x = 1").value
    assert_equal [true, {}], Predicator.execute_value([["lit", true], ["pop"]]).value
    stopped = Predicator.execute_value("x = 1; x / 0")

    refute_predicate stopped, :ok?
    assert_nil stopped.value
    assert_equal %w[EvaluationError division_by_zero], described(stopped.error)
  end

  # sabotage: run Lexer.tokenize's tokens through Parser.parse_program in
  # Predicator.parse; the root is a Program node, not a Comparison, and the
  # assert_respond_to fails.
  def test_parse_answers_the_tree
    tree = Predicator.parse("x > 1").value

    assert_respond_to tree, :operator
    assert_equal [:gt, "x", 1], [tree.operator, tree.left.name, tree.right.value]
    assert_raises(ArgumentError) { Predicator.parse(:x) }
  end

  # sabotage: answer Results.ok(tokens) for a refused scan in
  # Predicator.parse; "x & y" answers a token list and the assert_equal on
  # its error fails.
  def test_parse_refuses_what_compile_refuses_with_the_same_error
    ["x >", "x & y", "(", "x = 1"].each do |source|
      assert_equal Predicator.compile(source).error, Predicator.parse(source).error, source
    end
  end

  # sabotage: answer Results.ok(duration) whatever DurationText.read answers
  # in Predicator.parse_duration; "1x" answers a nil value and the
  # refute_predicate fails.
  def test_parse_duration_reads_the_literal_spelling_or_refuses_it
    assert_equal Predicator::Duration.new(hours: 1, minutes: 30), Predicator.parse_duration!("1h30m")
    assert_equal Predicator::Duration.new(seconds: 1, milliseconds: 500), Predicator.parse_duration!("1.5s")
    ["1x", "", "-1d", "1 d", "1.0001ms"].each do |text|
      refused = Predicator.parse_duration(text)

      refute_predicate refused, :ok?, text.inspect
      assert_equal %w[EvaluationError invalid_duration_format], described(refused.error)
    end
    assert_raises(ArgumentError) { Predicator.parse_duration(5) }
  end

  # Each bang variant, a call it answers and the value it answers it with.
  ANSWERED = [
    [:compile!, ["1"], [["lit", 1]]],
    [:compile_program!, ["x = 1"], [%w[lit x], ["lit", 1], ["store", 1]]],
    [:evaluate!, ["x + 1", { "x" => 1 }], 2],
    [:execute!, ["x = 1"], { "x" => 1 }],
    [:execute_value!, ["x = 1; x + 1"], [2, { "x" => 1 }]],
    [:parse_duration!, ["2d"], Predicator::Duration.new(days: 2)]
  ].freeze

  # Each bang variant, a call it refuses and the type of the error value
  # it raises.
  RAISED = [
    [:compile!, ["x >"], "ParseError"], [:compile_program!, ["x ="], "ParseError"],
    [:evaluate!, ["1 / 0"], "EvaluationError"], [:execute!, ["x = y + 1"], "UndefinedVariableError"],
    [:execute_value!, ["x = 1 / 0"], "EvaluationError"], [:parse!, ["("], "ParseError"],
    [:parse_duration!, ["d"], "EvaluationError"]
  ].freeze

  # sabotage: answer result.value whatever result.ok? says in
  # Predicator.unwrap; compile!("x >") answers nil and the assert_raises
  # fails.
  def test_each_bang_variant_raises_the_error_value_its_result_carries
    RAISED.each do |name, args, type|
      raised = assert_raises(Predicator::Error, name) { Predicator.public_send(name, *args) }

      assert_equal [type, raised.error.message], [raised.error.type, raised.message]
      assert_equal Predicator.public_send(name.to_s.delete_suffix("!"), *args).error, raised.error
    end
  end

  # sabotage: make Predicator.unwrap answer result itself; compile!("1")
  # answers the Result and the assert_equal fails.
  def test_each_bang_variant_answers_the_value_its_result_carries
    ANSWERED.each { |name, args, value| assert_equal value, Predicator.public_send(name, *args), name }
    assert_equal 1, Predicator.parse!("1").value
  end

  # sabotage: drop `clock: clock || SYSTEM_CLOCK` for `clock: SYSTEM_CLOCK`
  # in Evaluator.settings; Date.now() answers today, not the clock's noon,
  # and the first assert_equal fails.
  def test_the_clock_and_the_functions_are_keywords_of_the_call
    assert_equal NOON, Predicator.evaluate!("Date.now()", {}, clock: -> { NOON })
    assert_equal 42, Predicator.evaluate!("double(21)", {}, functions: { "double" => ->(n) { n * 2 } })
    assert_raises(ArgumentError) { Predicator.evaluate("1", {}, now: -> { NOON }) }
    assert_raises(ArgumentError) { Predicator.execute("x = 1", [], clock: -> { NOON }) }
  end

  # sabotage: hand Evaluator.evaluate no options (drop the `**` forwarding
  # in Predicator.evaluate); on_unbound: :error is ignored, missing OR true
  # answers true, and the refute_predicate fails.
  def test_the_unbound_policy_and_the_loop_budget_are_keywords_of_the_call
    strict = Predicator.evaluate("missing OR true", {}, on_unbound: :error)

    refute_predicate strict, :ok?
    assert_equal %w[UndefinedVariableError unbound_variable], described(strict.error)
    assert Predicator.evaluate!("missing OR true")
    assert_equal %w[EvaluationError loop_budget_exceeded],
                 described(Predicator.execute("while true { x = 1 }", {}, loop_budget: 3).error)
    assert_raises(ArgumentError) { Predicator.evaluate("1", {}, loop_budget: -1) }
  end
end
