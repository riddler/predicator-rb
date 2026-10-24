# frozen_string_literal: true

require "test_helper"

# The value boundary of the public entry points: a context, a literal
# operand and a host function's answer outside the value domain are refused
# with an error value, never raised, and a host function cannot change the
# context it reads.
class BoundaryTest < Minitest::Test
  def refused(result)
    refute_predicate result, :ok?, -> { "answered #{result.value.inspect}" }
    [result.error.type, result.error.reason]
  end

  def nested(levels) = (1...levels).reduce([]) { |inner, _| [inner] }

  def cycle = [].tap { |list| list << list }

  # sabotage: answer nil from Boundary.root_refusal; a nil root passes as
  # a map key the domain has, and refused's refute_predicate fails on
  # the second call.
  def test_a_context_key_must_be_a_string
    assert_equal %w[EvaluationError unsupported_host_value], refused(Predicator.evaluate("x OR true", { x: 1 }))
    assert_equal %w[EvaluationError unsupported_host_value], refused(Predicator.execute("y = 1", { nil => 1 }))
    assert_equal %w[EvaluationError unsupported_host_value], refused(Predicator.execute_value("1", { 1 => 1 }))
  end

  # sabotage: answer nil for every value in Boundary.leaf_fault's else
  # branch; a Symbol in the context is accepted and refused's
  # refute_predicate fails.
  def test_a_value_outside_the_domain_is_refused
    {
      :x => "unsupported_host_value", Time.at(0) => "unsupported_host_value", Float::NAN => "non_finite_number",
      -Float::INFINITY => "non_finite_number", "\xC3x".b => "unsupported_host_value",
      "\xC3x".dup.force_encoding(Encoding::UTF_8) => "unsupported_host_value",
      { "a" => [1, :y] } => "unsupported_host_value", { 1.5 => 1 } => "unsupported_host_value"
    }.each do |value, reason|
      assert_equal ["EvaluationError", reason], refused(Predicator.evaluate("x", { "x" => value })), value.inspect
    end
  end

  # sabotage: replace `depth > DEPTH_LIMIT` with `depth > DEPTH_LIMIT + 1`
  # in Check#container_fault; a context nesting 101 levels is accepted and
  # refused's refute_predicate fails on it.
  def test_an_over_deep_value_is_refused_without_raising
    assert_predicate Predicator.evaluate("1", { "x" => nested(99) }), :ok?
    assert_equal %w[EvaluationError depth_limit_exceeded], refused(Predicator.evaluate("1", { "x" => nested(100) }))
    assert_equal %w[EvaluationError depth_limit_exceeded], refused(Predicator.evaluate("1", { "x" => nested(50_000) }))
  end

  # sabotage: drop the :open test (the cyclic_value line) from
  # Check#container_fault; the cycle is walked round until it passes the
  # depth limit, is refused as depth_limit_exceeded, and the first
  # assert_equal fails.
  def test_a_cyclic_value_is_refused_without_raising
    assert_equal %w[EvaluationError cyclic_value], refused(Predicator.evaluate("x == x", { "x" => cycle }))
    map = { "a" => 1 }
    map["self"] = { "inner" => map }

    assert_equal %w[EvaluationError cyclic_value], refused(Predicator.execute("y = 1", { "m" => map }))
  end

  # sabotage: make Check#leave answer nil without marking the container
  # :done; the second path to the shared list finds it still open, it is
  # refused as cyclic, and the first assert_predicate fails.
  def test_a_shared_value_and_every_map_key_the_domain_has_are_accepted
    shared = [1, 2]
    wide = (1..40).reduce([1]) { |inner, _| [inner, inner] }

    assert_predicate Predicator.evaluate("x", { "x" => [shared, shared] }), :ok?
    assert_predicate Predicator.evaluate("x", { "x" => wide }), :ok?
    keys = { "s" => 1, 2 => 2, true => 3, false => 4, nil => 5, Predicator::UNDEFINED => 6 }

    assert_equal 2, Predicator.evaluate!("x[2]", { "x" => keys })
    assert_predicate Predicator.evaluate("x", { "x" => "text".encode(Encoding::US_ASCII) }), :ok?
  end

  # sabotage: answer nil in place of each literal's refusal in
  # Boundary.input_refusal; a Symbol literal is pushed and answered, and
  # refused's refute_predicate fails.
  def test_a_literal_operand_outside_the_domain_is_refused_before_anything_runs
    assert_equal %w[EvaluationError unsupported_host_value], refused(Predicator.evaluate([["lit", :x]]))
    assert_equal %w[EvaluationError cyclic_value],
                 refused(Predicator.execute([["lit", 1], ["pop"], ["lit", cycle], ["pop"]]))
    assert_match(/literal at index 2/, Predicator.execute([["lit", 1], ["pop"], ["lit", cycle], ["pop"]]).error.message)
  end

  # sabotage: call the host function with the arguments as they are (drop
  # `.map { |arg| Boundary.copy(arg) }` in Calls#host_call); the function's
  # writes reach the context and the assert_equal on it fails.
  def test_a_host_function_is_handed_copies_and_cannot_change_the_context
    context = { "l" => [+"a", { "k" => +"v" }], "s" => +"text" }
    grab = lambda do |list, text|
      list.push(3)[0] << "!"
      list[1]["k"] = text << "!"
      list.size
    end

    assert_equal 3, Predicator.evaluate!("grab(l, s)", context, functions: { "grab" => grab })
    assert_equal({ "l" => ["a", { "k" => "v" }], "s" => "text" }, context)
  end

  # sabotage: answer `@copies[member]` whether or not the member was
  # copied in Copy#take; the String and the Integer in the shared list are
  # answered as nil and the assert_equal fails.
  def test_a_shared_argument_is_copied_once_and_whole
    shared = ["a", 1]
    both = ->(list) { [list[0].equal?(list[1]), list[0]] }
    answer = Predicator.evaluate!("both(x)", { "x" => [shared, shared] }, functions: { "both" => both })

    assert_equal [true, shared], answer
  end

  # sabotage: answer Answered.new(answer) without the Boundary.refusal in
  # Calls#host_call; a Symbol answer is pushed and refused's
  # refute_predicate fails.
  def test_a_host_function_answer_outside_the_domain_is_refused
    { :x => "unsupported_host_value", Float::NAN => "non_finite_number", cycle => "cyclic_value",
      nested(101) => "depth_limit_exceeded" }.each do |answer, reason|
      result = Predicator.evaluate("f()", {}, functions: { "f" => -> { answer } })

      assert_equal ["EvaluationError", reason], refused(result)
      assert_match(/\AFunction f\(\) answered a value that/, result.error.message)
    end
    assert_equal [1, "a"], Predicator.evaluate!("f()", {}, functions: { "f" => -> { [1, "a"] } })
  end
end
