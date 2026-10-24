# frozen_string_literal: true

require "test_helper"
require_relative "evaluator_helper"
require_relative "json_reference_answers"

# JSON.stringify and JSON.parse, beyond what the corpus's cases pin.
class EvaluatorJsonTest < Minitest::Test
  include EvaluatorHelper
  include JsonReferenceAnswers

  def call(name, arg) = run_list([["lit", arg], ["call", name, 1]])

  def written(value)
    result = call("JSON.stringify", value)
    assert_predicate result, :ok?, -> { "failed with #{result.error.inspect}" }
    result.value
  end

  def read(text)
    result = call("JSON.parse", text)
    assert_predicate result, :ok?, -> { "failed with #{result.error.inspect}" }
    result.value
  end

  def refused(name, arg)
    result = call(name, arg)
    refute_predicate result, :ok?, -> { "answered #{result.value.inspect}" }
    result.error.reason
  end

  def nested(levels) = levels.times.reduce([]) { |inner, _| [inner] }

  # sabotage: write `value.keys.map` without `.sort` in
  # JsonFunctions.map; the keys come out in insertion order and the first
  # assert_equal fails.
  def test_stringify_sorts_keys_and_writes_floats_as_the_reference
    assert_equal '{"a":[1,1.0e3,0.5,null,true],"b":"x\"y"}',
                 written({ "b" => "x\"y", "a" => [1, 1000.0, 0.5, nil, true] })
  end

  # sabotage: write undefined as `"null"` in JsonFunctions.tagged; the
  # first assert_equal fails.
  def test_stringify_writes_the_values_json_has_no_form_for_as_the_reference
    date = Predicator::Date.new(year: 2024, month: 2, day: 29)
    instant = Predicator::DateTime.new(epoch_seconds: 0, microsecond: 5)
    assert_equal '["undefined","2024-02-29","1970-01-01T00:00:00.000005Z"]',
                 written([Predicator::UNDEFINED, date, instant])
    assert_equal '{"days":0,"hours":0,"milliseconds":0,"minutes":0,"months":0,"seconds":0,"weeks":2,"years":0}',
                 written(Predicator::Duration.new(weeks: 2))
  end

  # sabotage: re-raise NoForm in JsonFunctions#json_stringify instead of
  # answering the inspect; the call is refused and written's
  # assert_predicate fails.
  def test_stringify_writes_a_value_with_no_json_form_as_its_inspect
    assert_equal({ 1 => "x" }.inspect, written({ 1 => "x" }))
    invalid = "a\xFF".dup.force_encoding(Encoding::UTF_8)
    assert_equal [invalid].inspect, written([invalid])
    assert_equal "[:x]", written([:x])
  end

  # sabotage: compare `depth < DEPTH_LIMIT` in JsonFunctions.deep; a list
  # at the limit is refused and written's assert_predicate fails.
  def test_stringify_writes_to_the_depth_limit_and_refuses_past_it
    assert_equal "#{"[" * 100}#{"]" * 100}", written(nested(99))
    assert_equal "depth_limit_exceeded", refused("JSON.stringify", nested(100))
    cycle = []
    cycle << cycle
    assert_equal "depth_limit_exceeded", refused("JSON.stringify", cycle)
  end

  # sabotage: drop `@at = after` in JsonScan#trailing; "[1]  x" is refused
  # at the x, not the first space, and the assert_equal for it fails.
  def test_parse_refuses_a_malformed_text_where_the_reference_does
    FAULTS.each { |text, fault| assert_equal "Invalid JSON: #{fault}", refused("JSON.parse", text), text.inspect }
  end

  # sabotage: drop `sequence(start) if LOW.cover?(code)` in
  # JsonStrings#unicode; a lone low surrogate is read as a high one and
  # refused at the end of input, and the assert_equal for "\udc00x" fails.
  def test_parse_refuses_a_sequence_the_reference_cannot_read_at_its_start
    SEQUENCES.each do |text, at|
      assert_equal "Invalid JSON: unexpected sequence at position #{at}", refused("JSON.parse", text), text.inspect
    end
  end

  # sabotage: check `@open.size > @limit` in JsonScan#enter; 101 levels
  # are read and refused's refute_predicate fails.
  def test_parse_reads_to_the_depth_limit_and_refuses_past_it
    assert_equal nested(99), read("#{"[" * 100}#{"]" * 100}")
    assert_equal "depth_limit_exceeded", refused("JSON.parse", "#{"[" * 101}#{"]" * 101}")
  end

  # sabotage: drop the `sequence(start) if ...` line in
  # JsonScalars#number; 1e400 reads as Infinity and refused's
  # refute_predicate fails.
  def test_parse_reads_json_values_and_refuses_a_number_too_large
    assert_equal({ "a" => [1, -0.25, 100.0, "é/", nil, false], "b" => {} },
                 read(' {"a" : [1, -2.5e-1, 1E2, "\\u00e9\\/", null, false], "b":{}} '))
    assert_equal({ "a" => 2 }, read('{"a":1,"a":2}'))
    assert_equal [12, -500.0], [read("12"), read("-0.5e+3 ")]
    assert_equal "Invalid JSON: unexpected sequence at position 1", refused("JSON.parse", "[1e400]")
    assert_equal [0.0], read("[1e-400]")
    pairs = "[\"\\ud800\\udc00\", \"\\uDBFF\\uDFFF\", \"\u{1F600}\"]"
    assert_equal ["\u{10000}", "\u{10FFFF}", "\u{1F600}"], read(pairs)
    assert_equal "JSON.parse expects a string argument", refused("JSON.parse", 1)
  end

  # sabotage: read `@bytes = text.encode(Encoding::UTF_8)` in
  # JsonScan#initialize; a binary text's high bytes do not convert, the
  # call raises, and read's assert_predicate fails.
  def test_parse_reads_a_text_in_another_encoding_as_utf8
    parsed = read("[\"é\"]".b).first
    assert_equal Encoding::UTF_8, parsed.encoding
    assert_equal "é", parsed
    assert_equal "Invalid JSON: unexpected byte 0xFF at position 2", refused("JSON.parse", "[\"\xFF\"]".b)
  end
end
