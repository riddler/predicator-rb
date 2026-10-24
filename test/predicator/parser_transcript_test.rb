# frozen_string_literal: true

require "json"
require "test_helper"
require_relative "parser_helper"

# The parser against the vendored compile transcript
# (conformance/transcript/compile.json), the reference compiler's own
# answers. Its refusal rows (expressions) and program refusal rows
# (programs) carry the message, position and span of the refusal, and a
# refusal row also its reason; each is answered as the reference answers
# it, whether the lexer or the parser refuses it. Its compile and program
# rows each compile, so each parses. The instructions the rows carry, and
# the decompile rows, are not the parser's to answer.
class ParserTranscriptTest < Minitest::Test
  include ParserHelper

  DIR = File.expand_path("../../conformance/transcript", __dir__)
  ROWS = File.readlines(File.join(DIR, "compile.json"), chomp: true).map { |line| JSON.parse(line) }
  COUNTS = JSON.parse(File.read(File.join(DIR, "compile-SOURCE.json")))["counts"]

  def rows(kind) = ROWS.select { |row| row["kind"] == kind }

  def json_place(position) = { "column" => position.column, "line" => position.line }

  # The refusal the source gets, in the shape a refusal row records it.
  def observed(row, program:)
    result = program ? parse_program(row["source"]) : parse(row["source"])
    return "parsed" unless result.is_a?(REFUSAL)

    recorded = { "message" => result.error.message, "position" => json_place(result.error.position),
                 "reason" => result.error.reason, "span" => json_span(result.span) }
    recorded.slice(*row.keys)
  end

  def json_span(span) = { "end" => json_place(span.end), "start" => json_place(span.start) }

  def differing(kind, program:)
    rows(kind).filter_map do |row|
      want = row.slice("message", "position", "span", "reason")
      got = observed(row, program:)
      "#{row["id"]}\n  want #{want}\n  got  #{got}" unless got == want
    end
  end

  # sabotage: name the end of input "end of the input" in
  # TokenText::FIXED; the refusal/expected_close_brace row differs and the
  # assert_empty fails.
  def test_every_refusal_row_is_refused_as_the_reference_refuses_it
    differing = differing("refusal", program: false)

    assert_empty differing, differing.join("\n")
  end

  # sabotage: refuse a stray `else` under the trailing-token message in
  # Statements#after_statement (drop its first line); the
  # program-refusal/stray-else/after-statement row differs and the
  # assert_empty fails.
  def test_every_program_refusal_row_is_refused_as_the_reference_refuses_it
    differing = differing("program_refusal", program: true)

    assert_empty differing, differing.join("\n")
  end

  # sabotage: set Parser::DEPTH_LIMIT to 256; the 300-parenthesis compile
  # row is refused and the first assert_empty fails.
  def test_every_compile_row_parses_as_an_expression_and_every_program_row_as_a_program
    refused = rows("compile").reject { |row| observed(row, program: false) == "parsed" }.map { |row| row["id"] }

    assert_empty refused
    refused = rows("program").reject { |row| observed(row, program: true) == "parsed" }.map { |row| row["id"] }

    assert_empty refused
  end

  # sabotage: read only the first line of compile.json into ROWS
  # (`.first(1)`); the row count differs from the record's and the first
  # assert_equal fails.
  def test_every_row_the_transcript_record_counts_is_read
    assert_equal COUNTS["rows"], ROWS.size
    assert_equal COUNTS.except("rows"), ROWS.map { |row| row["kind"] }.tally
  end

  # sabotage: scan a single `&` as `&&` (add `"&" => :and_and` to
  # Lexer::OPERATORS); the unexpected-character row lexes, nine reads
  # eight and the assert_equal fails.
  def test_the_lexer_refuses_nine_rows_and_the_parser_the_other_forty_seven
    lexed = (rows("refusal") + rows("program_refusal")).count { |row| tokenize(row["source"]).is_a?(REFUSAL) }

    assert_equal [9, 18, 29], [lexed, rows("refusal").size - lexed, rows("program_refusal").size]
  end
end
