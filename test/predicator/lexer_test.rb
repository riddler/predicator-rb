# frozen_string_literal: true

require "test_helper"
require_relative "lexer_helper"

# What the tokens transcript does not record: each token's value, and the
# reference lexer's answers at the edges no transcript row reaches.
class LexerTest < Minitest::Test
  include LexerHelper

  FRACTION = LEXER.const_get(:Fraction)

  def date(year, month, day) = Predicator::Date.new(year:, month:, day:)

  # sabotage: read every number as an Integer (`Integer(whole, 10)` for
  # `Float(text)` in Numbers#number); 1.5 reads as 1 and the first
  # assert_equal fails.
  def test_a_number_carries_its_value
    assert_equal [[:float, 1, 1, 3, 1.5], [:integer, 1, 5, 3, 7], [:eof, 1, 8, 0, nil]], scanned("1.5 007")
    assert_equal 12_345_678_901_234_567_890, scanned("12345678901234567890").first.last
    assert_equal [[:fractional_number, 1, 1, 6, FRACTION.new(whole: 7, fraction: "50")],
                  [:duration_unit, 1, 7, 1, "h"], [:eof, 1, 8, 0, nil]], scanned("007.50h")
    assert_equal Float::INFINITY, scanned("#{"9" * 400}.5").first.last
  end

  # sabotage: map "true" to [:boolean, false] in Lexer::RESERVED; the
  # first assert_equal fails.
  def test_a_reserved_word_carries_its_value_and_keeps_its_type_before_a_parenthesis
    assert_equal [true, false, Predicator::UNDEFINED, nil, "AND", "contains", "last"],
                 scanned("true false undefined null AND contains last").map(&:last).first(7)
    assert_equal %i[and_op lparen identifier rparen eof], scanned("and(x)").map(&:first)
    assert_equal %i[function_name lparen rparen eof], scanned("True ()").map(&:first)
  end

  # sabotage: drop the "n" entry of Literals::ESCAPES; `\n` decodes to the
  # letter n and the first assert_equal fails.
  def test_a_string_decodes_its_escapes_and_an_unknown_escape_stands_for_its_letter
    assert_equal "a\nb\tc\rd\"e'f\\g", scanned(%q("a\nb\tc\rd\"e\'f\\\\g")).first.last
    assert_equal "visaqgold", scanned(%q("visa\qgold")).first.last
    assert_equal "it's", scanned(%q("it's")).first.last
    assert_equal "caf\u00e9", scanned("'caf\u00e9'").first.last
  end

  # sabotage: pass the literal's text to `after` as it is in
  # Literals#string (drop the gsub of escape pairs); the escaped line feed
  # moves the line and the first assert_equal fails.
  def test_an_escaped_line_feed_advances_the_column_by_two_and_not_the_line
    assert_equal [[:string, 1, 1, 6, "a\nb"], [:identifier, 1, 8, 1, "x"], [:eof, 1, 9, 0, nil]],
                 scanned(%("a\\\nb" x))
    end_position = tokenize(%("a\\\nb" x)).first.end_position
    assert_equal [1, 7], [end_position.line, end_position.column]
  end

  # sabotage: try the one-letter units first (`[ydhmsw]|m[so]` for
  # Numbers::UNIT); `ms` reads as `m` then `s` and the first assert_equal
  # fails.
  def test_duration_units_are_read_one_after_another_the_two_letter_ones_first
    assert_equal [[:integer, 1, 1, 1, 5], [:duration_unit, 1, 2, 1, "d"], [:duration_unit, 1, 3, 1, "h"],
                  [:duration_unit, 1, 4, 2, "ms"], [:eof, 1, 6, 0, nil]], scanned("5dhms")
    assert_equal ["mo", 1, "d"], scanned("5mo1d").map(&:last)[1, 3]
    assert_equal %i[integer identifier], scanned("5 m").map(&:first).first(2)
  end

  # sabotage: go on over the whole rest of the source after a duration
  # (`return ""` at the head of Numbers#keep_line); `y` on the next line
  # is read and the first assert_equal fails.
  def test_the_scan_stops_at_the_first_line_feed_after_a_duration_as_the_reference_does
    assert_equal [[:integer, 1, 1, 1, 5], [:duration_unit, 1, 2, 1, "d"], [:identifier, 1, 6, 1, "x"],
                  [:eof, 1, 7, 0, nil]], scanned("5d x\ny")
    assert_equal [[:identifier, 1, 5, 1, "x"], [:eof, 1, 6, 0, nil]], scanned("5d x\r\ny").last(2)
    assert_equal [:identifier, 2, 1, 3, "foo"], scanned("5d\nfoo\nbar")[2]
    assert_equal [:eof, 2, 1, 0, nil], scanned("5h\n\n x").last
  end

  # The reference's answers, read from its compiled build at v9.5.0, where
  # a run of units is followed by text that holds a line feed: the kept
  # text starts after the first unit, so a line feed right after the last
  # unit of a longer run drops the rest.
  UNIT_RUNS = {
    "5dh\nx\ny" => [[:integer, 1, 1, 1, 5], [:duration_unit, 1, 2, 1, "d"], [:duration_unit, 1, 3, 1, "h"],
                    [:eof, 1, 8, 0, nil]],
    "next 2dh\n+ 1" => [[:next_op, 1, 1, 4, "next"], [:integer, 1, 6, 1, 2], [:duration_unit, 1, 7, 1, "d"],
                        [:duration_unit, 1, 8, 1, "h"], [:eof, 1, 13, 0, nil]],
    "5msh\nz" => [[:integer, 1, 1, 1, 5], [:duration_unit, 1, 2, 2, "ms"], [:duration_unit, 1, 4, 1, "h"],
                  [:eof, 1, 7, 0, nil]],
    "5dh\r\nx" => [[:integer, 1, 1, 1, 5], [:duration_unit, 1, 2, 1, "d"], [:duration_unit, 1, 3, 1, "h"],
                   [:eof, 1, 5, 0, nil]],
    "5dh x\ny" => [[:integer, 1, 1, 1, 5], [:duration_unit, 1, 2, 1, "d"], [:duration_unit, 1, 3, 1, "h"],
                   [:identifier, 1, 7, 1, "x"], [:eof, 1, 8, 0, nil]],
    "5d\nfoo\nbar" => [[:integer, 1, 1, 1, 5], [:duration_unit, 1, 2, 1, "d"], [:identifier, 2, 1, 3, "foo"],
                       [:eof, 2, 4, 0, nil]],
    "5dhms\n1" => [[:integer, 1, 1, 1, 5], [:duration_unit, 1, 2, 1, "d"], [:duration_unit, 1, 3, 1, "h"],
                   [:duration_unit, 1, 4, 2, "ms"], [:eof, 1, 8, 0, nil]],
    "1.5hm\nx" => [[:fractional_number, 1, 1, 3, FRACTION.new(whole: 1, fraction: "5")],
                   [:duration_unit, 1, 4, 1, "h"], [:duration_unit, 1, 5, 1, "m"], [:eof, 1, 8, 0, nil]]
  }.freeze

  # sabotage: keep the text after the last unit instead of the first (move
  # `dropped ||= keep_line` after the loop in Numbers#units, as
  # `dropped = keep_line`); "5dh\nx\ny" reads `x` on line 2 and the
  # assert_empty fails.
  def test_a_run_of_units_keeps_the_text_after_its_first_unit_as_the_reference_does
    differing = UNIT_RUNS.reject { |source, tokens| scanned(source) == tokens }.keys

    assert_empty differing
    assert_equal ["unexpected_character", [1, 4]], refusal("5d\u0301h\nx").values_at(0, 2)
  end

  # sabotage: count the units' characters (`unit_text.length` for the
  # grapheme count in Numbers#consumed); the combining mark is refused at
  # column 3 and the first assert_equal fails.
  def test_the_column_after_duration_units_counts_grapheme_clusters_as_the_reference_does
    assert_equal ["unexpected_character", "Unexpected character '\u0301'", [1, 2], [1, 2], [1, 3]],
                 refusal("5d\u0301")
    assert_equal [1, 5], refusal("5d\u00e9\nx")[2]
    assert_equal [:eof, 1, 4, 0, nil], scanned("1h\r\n2").last
  end

  # sabotage: look for the parenthesis only right after the name (`/\(/`
  # for `/[ \t\r\n]*\(/` in Scan#call_follows?); "a.b" before a line feed
  # and "(" is not one token and the second assert_equal fails.
  def test_a_dotted_name_is_one_token_only_where_a_call_follows_it
    assert_equal %i[identifier dot identifier dot identifier eof], scanned("a.b.c").map(&:first)
    assert_equal [[:qualified_function_name, 1, 1, 3, "a.b"], [:lparen, 2, 1, 1, "("]], scanned("a.b\n(1)").first(2)
    assert_equal [:qualified_function_name, 1, 1, 5, "a.and"], scanned("a.and(x)").first
    assert_equal %i[identifier dot and_op dot identifier eof], scanned("a.and.b").map(&:first)
  end

  # sabotage: read a datetime body with IsoText.read_datetime (bounded) in
  # Literals#read_date; the year-10000 instant is refused and `scanned`
  # flunks on it in the second assertion.
  def test_a_date_literal_carries_its_value_and_a_datetime_is_unbounded_in_its_year
    assert_equal date(-1, 1, 1), scanned("#-0001-01-01#").first.last
    instant = scanned("#9999-12-31T23:00:00-05:00#").first.last
    assert_equal date(10_000, 1, 1), CIVIL.date_of(instant)
  end

  # sabotage: apply no offset (return 0 at the head of IsoText.read_offset);
  # the instant reads as 10:00 UTC and the assert_equal fails.
  def test_a_datetime_literal_applies_its_offset
    assert_equal CIVIL.instant_at(date(2024, 1, 15), 4, 30), scanned("#2024-01-15T10:00:00+05:30#").first.last
  end

  # sabotage: read every body as a date (`return [:date, ...]` first in
  # Literals#read_date); the datetime refusal names a date and the first
  # assert_equal fails.
  def test_a_date_literal_the_reference_refuses_is_refused_over_the_whole_literal
    assert_equal ["invalid_datetime", "Invalid datetime format: 2024-01-15T10:00:00", [1, 1], [1, 1], [1, 22]],
                 refusal("#2024-01-15T10:00:00#")
    assert_equal "Invalid date format: 20240115", refusal("#20240115#")[1]
    assert_equal "Invalid date format: 2024-01-15t10:00:00Z", refusal("#2024-01-15t10:00:00Z#")[1]
    assert_equal ["unterminated_date", "Unterminated date literal", [1, 1], [1, 1], [1, 6]], refusal("#2024")
  end

  # sabotage: let each offset field take a sign in IsoText (`[-0-9][0-9]`
  # for `[0-9]{2}` in the offset of IsoText::DATETIME_TEXT and in
  # IsoText::OFFSET_TEXT); the literal scans and `refusal` flunks.
  def test_a_signed_offset_field_is_refused_where_the_reference_reads_an_instant
    assert_equal "invalid_datetime", refusal("#2024-01-15T10:00:00+-5:30#").first
  end

  # sabotage: drop the `%w[u U].include?` refusal in Literals#escape; the
  # escape decodes to its letter and `refusal` flunks in the first
  # assertion.
  def test_refusals_name_their_reason
    assert_equal "unsupported_escape", refusal(%q("a\U0041")).first
    assert_equal ["unterminated_string", [1, 1], [1, 2]], refusal("'a\\").values_at(0, 3, 4)
    assert_equal ["unexpected_character", "Unexpected character '\u00a0'", [1, 2], [1, 2], [1, 3]],
                 refusal("x\u00a0y")
  end
end
