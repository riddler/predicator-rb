# frozen_string_literal: true

require "json"
require "test_helper"
require "predicator/tagged"
require_relative "parser_helper"
require_relative "../conformance/attempts"

# Predicator.compile and Predicator.compile_program against the vendored
# compile transcript (conformance/transcript/compile.json), the reference
# compiler's own answers:
#
# - a compile row by its instruction list, read through the tagged codec
#   and compared operand by operand (an Integer is not a Float);
# - a program row by its instruction list, and by the span of the node
#   behind each instruction and behind each segment each store writes;
# - a refusal row by its reason, message and position, and a program
#   refusal row by its message and position (the parser's suite holds both
#   to their spans as well).
#
# Its decompile rows render a syntax tree back to text, which this package
# has no function for; they are counted, not answered.
class CompileTranscriptTest < Minitest::Test
  include ParserHelper

  DIR = File.expand_path("../../conformance/transcript", __dir__)
  ROWS = File.readlines(File.join(DIR, "compile.json"), chomp: true).map { |line| JSON.parse(line) }
  COUNTS = JSON.parse(File.read(File.join(DIR, "compile-SOURCE.json")))["counts"]
  EMITTER = Predicator.const_get(:Emitter)

  def rows(kind) = ROWS.select { |row| row["kind"] == kind }

  # A row's instruction list as predicator values, read as the corpus is.
  def decoded(instructions) = Predicator::Tagged.decode!(JSON.generate(instructions))

  def same?(compiled, row) = Conformance::Attempts.identical?(compiled, decoded(row["instructions"]))

  def json_place(position) = { "column" => position.column, "line" => position.line }
  def json_span(span) = { "end" => json_place(span.end), "start" => json_place(span.start) }

  # The rows of a kind whose instruction lists the call does not reproduce.
  def differing_lists(kind)
    rows(kind).filter_map do |row|
      result = yield row["source"]
      got = result.ok? ? result.value : "refused: #{result.error.message}"
      "#{row["id"]}\n  want #{row["instructions"]}\n  got  #{got.inspect}" unless result.ok? && same?(got, row)
    end
  end

  # The program's spans, in the shape a program row records them.
  def recorded_spans(source)
    indexed = EMITTER.emit_program(parse_program(source)).each_with_index
    positions = indexed.map { |entry, index| { "instruction" => index, "span" => json_span(entry.span) } }
    segments = indexed.select { |entry, _| entry.segments }.map do |entry, index|
      { "instruction" => index, "spans" => entry.segments.map { |node| json_span(node.span) } }
    end
    { "positions" => positions, "segment_positions" => segments }
  end

  # The refusal compile or compile_program answers, in the shape a refusal
  # row records it.
  def refusal_of(source, program:)
    result = program ? Predicator.compile_program(source) : Predicator.compile(source)
    return "compiled" if result.ok?

    { "message" => result.error.message, "position" => json_place(result.error.position),
      "reason" => result.error.reason }
  end

  # sabotage: emit `jump_if_true_or_pop` for `and` in Chains#jump_over (swap the
  # two opcode strings); the and/or compile rows differ and the
  # assert_empty fails.
  def test_every_compile_row_compiles_to_the_reference_instructions
    differing = differing_lists("compile") { |source| Predicator.compile(source) }

    assert_empty differing, differing.join("\n")
  end

  # sabotage: count a while's back edge one short (drop the `+ 1` from the
  # jump_backward offset in Statements#while_statement); the while program rows
  # differ and the assert_empty fails.
  def test_every_program_row_compiles_to_the_reference_instructions
    differing = differing_lists("program") { |source| Predicator.compile_program(source) }

    assert_empty differing, differing.join("\n")
  end

  # sabotage: give a store its root's span instead of its statement's (pass
  # `span: root.span` in Statements#assignment); every assignment row's store
  # span differs and the assert_empty fails.
  def test_every_program_row_carries_the_reference_spans
    differing = rows("program").filter_map do |row|
      want = row.slice("positions", "segment_positions")
      got = recorded_spans(row["source"])
      "#{row["id"]}\n  want #{want}\n  got  #{got}" unless got == want
    end

    assert_empty differing, differing.join("\n")
  end

  # sabotage: blank the message of the error Predicator.compiled answers
  # (`entries.error.with(message: "")`); every refusal row differs and the
  # first assert_empty fails.
  def test_every_refusal_row_is_refused_by_compile_and_every_program_refusal_row_by_compile_program
    [["refusal", false], ["program_refusal", true]].each do |kind, program|
      differing = rows(kind).filter_map do |row|
        want = row.slice("message", "position", "reason")
        got = refusal_of(row["source"], program:)
        got = got.slice(*want.keys) if got.is_a?(Hash)
        "#{row["id"]}\n  want #{want}\n  got  #{got}" unless got == want
      end

      assert_empty differing, differing.join("\n")
    end
  end

  # sabotage: read only the first line of compile.json into ROWS
  # (`.first(1)`); the decompile count reads 0 and the assert_equal fails.
  def test_the_decompile_rows_are_counted_and_every_other_kind_is_answered
    answered = %w[compile refusal program program_refusal].sum { |kind| rows(kind).size }

    assert_equal [COUNTS["decompile"], COUNTS["rows"] - COUNTS["decompile"]], [rows("decompile").size, answered]
    assert_equal 45, rows("decompile").size
  end
end
