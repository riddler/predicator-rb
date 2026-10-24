# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"
require_relative "parser_helper"

# The emitter, reached as the compiler reaches it: a syntax tree in, the
# annotated instructions or a refusal out.
class EmitterTest < Minitest::Test
  include ParserHelper

  EMITTER = Predicator.const_get(:Emitter)
  LIB = File.expand_path("../../lib", __dir__)
  TOO_LARGE = "#{"9" * 400}.5".freeze

  def emitted(source) = EMITTER.emit(parse(source))
  def emitted_program(source) = EMITTER.emit_program(parse_program(source))
  def place(position) = [position.line, position.column]

  def refusal_parts(refusal)
    [refusal.error.reason, refusal.error.message, place(refusal.error.position), place(refusal.span.start),
     place(refusal.span.end)]
  end

  # What a fresh interpreter, warning at its most verbose, prints to
  # standard error while it compiles the sources.
  def warnings_compiling(sources)
    script = %(require "predicator"\n#{sources.inspect}.each { |source| Predicator.compile(source) })
    _, errors, status = Open3.capture3(RbConfig.ruby, "-W2", "-I", LIB, "-e", script)
    assert_predicate status, :success?
    errors
  end

  # sabotage: drop the refuse in Walk#value_of; the literal emits
  # ["lit", Infinity], the walk answers a list and the first
  # assert_instance_of fails.
  def test_a_decimal_too_large_for_a_finite_float_is_refused_over_the_literal
    [TOO_LARGE, "x + #{TOO_LARGE}", "[1, #{TOO_LARGE}]"].each do |source|
      column = source.index("9") + 1
      refusal = emitted(source)

      assert_instance_of REFUSAL, refusal
      assert_equal ["number_out_of_range", "Number literal is outside the range this implementation can represent",
                    [1, column], [1, column], [1, column + TOO_LARGE.size]], refusal_parts(refusal)
    end
  end

  # sabotage: read a decimal with Float(text) in Numbers#number again; the
  # interpreter prints an out-of-range warning and the assert_empty fails.
  def test_no_source_makes_the_host_print_a_warning
    assert_empty warnings_compiling([TOO_LARGE, "0.#{"0" * 400}1", "[0.#{"0" * 330}1, 1.5]"])
  end

  # sabotage: answer nil from FloatText.read at or below FLOOR; the decimal
  # reads as infinite, is refused, and the assert_equal fails.
  def test_a_decimal_too_close_to_zero_for_another_float_compiles_to_zero
    assert_equal [["lit", 0.0]], Predicator.compile("0.#{"0" * 400}1").value
    assert_equal [["lit", 5.0e-321]], Predicator.compile("0.#{"0" * 320}5").value
  end

  # sabotage: walk a chain recursively (make Chains#chain answer
  # `link(root, visit(leaning(root)))`); the long spine exhausts the
  # Fiber's stack, the walk answers a refusal and the first
  # assert_instance_of fails.
  def test_a_chain_of_any_length_is_walked_in_a_loop
    links = 20_000
    entries = on_a_fiber { emitted((["a"] * links).join(" or ")) }

    assert_instance_of Array, entries
    assert_equal (2 * links) - 1, entries.size
    entries = on_a_fiber { emitted("a#{".b" * links}::string") }

    assert_equal %w[cast string], entries.last.instruction
  end

  # sabotage: let a SystemStackError through (drop the rescue in Walk#run);
  # the Fiber answers the error rather than a refusal and the
  # assert_instance_of fails.
  def test_a_tree_deeper_than_the_stack_is_refused_rather_than_raising
    leaf = AST::Identifier.new(name: "x", position: Predicator::Position.new(line: 1, column: 1), span: nil)
    deep = (1..200_000).reduce(leaf) { |operand, _| AST::LogicalNot.new(operand:, position: leaf.position, span: nil) }
    refusal = on_a_fiber { EMITTER.emit(deep) }

    assert_instance_of REFUSAL, refusal
    assert_equal "nesting_depth_exceeded", refusal.error.reason
    assert_match(/deeper than the stack this compilation runs on can follow/, refusal.error.message)
  end

  # sabotage: give an object_set the object's node (own(node, ...) in
  # Walk#object); its position is the brace's and the assert_equal fails.
  def test_each_instruction_carries_the_position_of_the_node_that_emitted_it
    positions = emitted("{a: x, b: 1} == y").map { |entry| [entry.instruction.first, place(entry.position)] }

    assert_equal [["object_new", [1, 1]], ["load", [1, 5]], ["object_set", [1, 2]], ["lit", [1, 11]],
                  ["object_set", [1, 8]], ["load", [1, 17]], ["compare", [1, 14]]], positions
  end

  # sabotage: give a store the assignment's position (node.position for
  # root.position in Statements#assignment); it reads the `=` and the
  # assert_equal fails.
  def test_a_store_carries_its_root_and_the_node_behind_each_segment
    store = emitted_program("a.b[k + 1] = 2").last

    assert_equal [["store", 3], [1, 1]], [store.instruction, place(store.position)]
    assert_equal([[1, 1], [1, 3], [1, 7]], store.segments.map { |node| place(node.position) })
    assert_nil emitted_program("a").first.segments
  end

  # sabotage: never fold (`if false` for the all-literals test in
  # Walk#list); the literal list is made with make_list and the first
  # assert_equal fails.
  def test_a_list_of_literals_folds_and_any_other_list_is_made
    assert_equal [["lit", [1, "s", nil, Predicator::UNDEFINED]]],
                 emitted("[1, 's', null, undefined]").map(&:instruction)
    assert_equal [["lit", 1], %w[load x], ["make_list", 2]], emitted("[1, x]").map(&:instruction)
    assert_equal [["lit", 1], ["lit", [2]], ["make_list", 2]], emitted("[1, [2]]").map(&:instruction)
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
