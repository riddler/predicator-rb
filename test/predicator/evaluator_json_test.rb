# frozen_string_literal: true

require "test_helper"
require_relative "evaluator_helper"

# JSON.stringify and JSON.parse, beyond what the corpus's cases pin.
class EvaluatorJsonTest < Minitest::Test
  include EvaluatorHelper

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
    assert_equal '{1 => "x"}', written({ 1 => "x" })
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

  # sabotage: drop the `raise Calls::Refusal, fault` line in
  # JsonFunctions#json_parse; Ruby's parser raises, its sentence is the
  # reason, and the assert_equal for "[1,]" fails.
  def test_parse_refuses_a_malformed_text_at_its_first_fault
    {
      "[1,]" => "unexpected byte 0x5D at position 3", "tru" => "unexpected end of input at position 3",
      "01" => "unexpected byte 0x31 at position 1", "1.e1" => "unexpected byte 0x65 at position 2",
      '{"a" 1}' => "unexpected byte 0x31 at position 5", "{1:2}" => "unexpected byte 0x31 at position 1",
      '"\\q"' => "unexpected byte 0x71 at position 2", '"\\u00G0"' => "unexpected byte 0x47 at position 5",
      "\"a\u0001\"" => "unexpected byte 0x01 at position 2", "[1 2]" => "unexpected byte 0x32 at position 3",
      "\"é\xFF\"".dup.force_encoding(Encoding::UTF_8) => "unexpected byte 0xFF at position 3",
      "" => "unexpected end of input at position 0", "1 x" => "unexpected byte 0x78 at position 2"
    }.each { |text, fault| assert_equal "Invalid JSON: #{fault}", refused("JSON.parse", text), text.inspect }
  end

  # sabotage: check `@open.size > @limit` in JsonScan#enter; 101 levels
  # are read and refused's refute_predicate fails.
  def test_parse_reads_to_the_depth_limit_and_refuses_past_it
    assert_equal nested(99), read("#{"[" * 100}#{"]" * 100}")
    assert_equal "depth_limit_exceeded", refused("JSON.parse", "#{"[" * 101}#{"]" * 101}")
  end

  # sabotage: answer the parsed value without JsonFunctions.finite in
  # JsonFunctions#json_parse; 1e400 reads as Infinity and refused's
  # refute_predicate fails.
  def test_parse_reads_json_values_and_refuses_a_number_too_large
    assert_equal({ "a" => [1, -0.25, 100.0, "é/", nil, false], "b" => {} },
                 read(' {"a" : [1, -2.5e-1, 1E2, "\\u00e9\\/", null, false], "b":{}} '))
    assert_equal({ "a" => 2 }, read('{"a":1,"a":2}'))
    assert_equal [12, -500.0], [read("12"), read("-0.5e+3 ")]
    assert_equal "Invalid JSON: a number is too large for a float", refused("JSON.parse", "[1e400]")
    assert_equal "JSON.parse expects a string argument", refused("JSON.parse", 1)
  end

  # sabotage: answer `text` for `text.dup.force_encoding(Encoding::UTF_8)`
  # in JsonFunctions#json_parse; the binary text is valid as binary, its
  # byte 0xFF is not refused, and refused's refute_predicate fails.
  def test_parse_reads_a_text_in_another_encoding_as_utf8
    assert_equal ["é"], read("[\"é\"]".b)
    assert_equal "Invalid JSON: unexpected byte 0xFF at position 2", refused("JSON.parse", "[\"\xFF\"]".b)
  end
end
