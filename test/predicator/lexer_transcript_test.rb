# frozen_string_literal: true

require "json"
require "test_helper"
require_relative "lexer_helper"

# The scanner against every row of the vendored tokens transcript
# (conformance/transcript/tokens.json), the reference lexer's own answers:
# a tokens row by each token's type, line, column and length, and a string
# token's quote and end; a refusal row by its message, position and span.
class LexerTranscriptTest < Minitest::Test
  include LexerHelper

  DIR = File.expand_path("../../conformance/transcript", __dir__)
  ROWS = File.readlines(File.join(DIR, "tokens.json"), chomp: true).map { |line| JSON.parse(line) }
  COUNTS = JSON.parse(File.read(File.join(DIR, "tokens-SOURCE.json")))["counts"]

  # sabotage: count a carriage return outside a literal as a column (drop
  # `elsif char != "\r"` to `else` in Scan#blank); the "limit\r > 5" row
  # differs and the assert_empty fails.
  def test_every_row_is_answered_as_the_reference_answers_it
    differing = ROWS.filter_map do |row|
      observed = observed_row(row["source"])
      "#{row["source"].inspect}\n  want #{row}\n  got  #{observed}" unless observed == row
    end

    assert_empty differing, differing.join("\n")
  end

  # sabotage: read only the first line of tokens.json in ROWS (`.first(1)`);
  # the row count differs from the transcript record's and the first
  # assert_equal fails.
  def test_every_row_the_transcript_record_counts_is_read
    kinds = ROWS.map { |row| row["kind"] }.tally

    assert_equal COUNTS["rows"], ROWS.size
    assert_equal({ "tokens" => COUNTS["tokens"], "refusal" => COUNTS["refusal"] }, kinds)
  end
end
