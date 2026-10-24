# frozen_string_literal: true

require_relative "tagged_helper"

# The codec over the values JSON carries as themselves, and what it refuses
# whatever the value.
class TaggedJsonTest < Minitest::Test
  include TaggedHelper

  # sabotage: add `when Integer then json.to_f` to Reader.value; the
  # assert_equal on the typed integer 1 fails.
  def test_json_values_decode_to_themselves_with_integer_and_float_apart
    value = decoded('[1,1.0,-0.0,1e2,"x",true,false,null,[],{"a":{"b":[2]}}]')

    assert_equal typed([1, 1.0, -0.0, 100.0, "x", true, false, nil, [], { "a" => { "b" => [2] } }]), typed(value)
    assert_equal(-Float::INFINITY, 1.0 / value[2])
  end

  # sabotage: write value.to_i.to_s for an integral Float in Writer.float;
  # the text then reads 1 for 1.0 and the assert_equal fails.
  def test_json_values_encode_with_integer_and_float_apart
    assert_equal '[1,1.0,-0.0,1.0e+20,"x\\"y",true,false,null,[],{"a":{}}]',
                 Tagged.encode!([1, 1.0, -0.0, 1e20, "x\"y", true, false, nil, [], { "a" => {} }])
    assert_equal typed(12_345_678_901_234_567_890), typed(decoded(Tagged.encode!(12_345_678_901_234_567_890)))
    assert_equal "[[1],[1]]", Tagged.encode!([[1]] * 2)
    assert_equal '["x","1"]', Tagged.encode!(["x".b, 1.to_s])
  end

  # sabotage: answer nil from Reader.tag for the undefined tag (reading it
  # as null); the assert_same fails.
  def test_the_undefined_tag_is_undefined_and_not_null
    assert_same Predicator::UNDEFINED, decoded('{"$type":"undefined"}')
    assert_equal '{"$type":"undefined"}', Tagged.encode!(Predicator::UNDEFINED)
    assert_equal "null", Tagged.encode!(nil)
    assert_equal "invalid_tagged_value", refusal(Tagged.decode('{"$type":"undefined","value":null}'))
  end

  # sabotage: answer json.transform_values from Reader.map whatever its
  # keys; the unknown tag decodes as a map and the assert_equal fails.
  def test_an_object_with_a_type_key_is_a_tag_or_a_refusal
    ['{"$type":"date"}', '{"$type":"money","value":1}', '{"$type":"date","value":"2026-08-06","x":1}',
     '{"$type":1}', '{"$type":"date","value":1e999}',
     %({"$type":"date","value":#{"[" * 98}#{"]" * 98}})].each do |text|
      assert_equal "invalid_tagged_value", refusal(Tagged.decode(text)), text
    end
  end

  # sabotage: drop the reserved-key test from Writer.map; the map is written
  # and the assert_equal on its refusal fails.
  def test_a_map_with_a_type_key_is_not_encoded
    assert_equal "reserved_map_key", refusal(Tagged.encode({ "a" => [{ "$type" => "date" }] }))
  end

  # sabotage: make Reader.finite answer the number whatever it is; the
  # infinity decodes and the assert_equal on its refusal fails.
  def test_a_text_that_is_not_json_or_holds_no_finite_number_is_refused
    assert_equal "malformed_json", refusal(Tagged.decode("[1,"))
    assert_equal "malformed_json", refusal(Tagged.decode("[NaN]"))
    assert_equal "malformed_json", refusal(Tagged.decode((+"\"\xFF\"").force_encoding(Encoding::BINARY)))
    assert_equal "non_finite_number", refusal(Tagged.decode("[1e400]"))
    assert_raises(ArgumentError) { Tagged.decode(nil) }
  end

  # sabotage: drop the finite test from Writer.float; NaN is written and the
  # assert_equal on its refusal fails.
  def test_a_value_outside_the_domain_is_not_encoded
    cyclic = [1]
    cyclic << cyclic

    assert_equal %w[non_finite_number cyclic_value],
                 [refusal(Tagged.encode(Float::NAN)), refusal(Tagged.encode(cyclic))]
    unencodable = [:x, { x: 1 }, (+"\xFF").force_encoding(Encoding::BINARY), +"\xFF"]

    assert_equal(%w[unsupported_value] * 4, unencodable.map { |bad| refusal(Tagged.encode(bad)) })
  end

  def nested(depth, inner = "") = "#{"[" * depth}#{inner}#{"]" * depth}"
  def nested_maps(depth) = "#{'{"a":' * (depth - 1)}{}#{"}" * (depth - 1)}"
  def wrapped(depth, inner) = depth.times.reduce(inner) { |value, _| [value] }

  # sabotage: compare depth < DEPTH_LIMIT in Reader.deep; the text nested
  # exactly to the limit is refused and the assert_equal on [true, true]
  # fails.
  def test_decode_reads_a_text_nested_to_the_depth_limit
    limit = Tagged::DEPTH_LIMIT

    assert_equal([true, true], [nested(limit), nested_maps(limit)].map { |text| Tagged.decode(text).ok? })
  end

  # sabotage: compare depth <= DEPTH_LIMIT + 1 in Reader.deep; the texts one
  # level past the limit decode and the assert_equal on the refusals fails.
  def test_decode_refuses_a_text_nested_past_the_depth_limit
    limit = Tagged::DEPTH_LIMIT
    too_deep = [nested(limit + 1), nested_maps(limit + 1), nested(1000),
                nested(limit - 1, %({"$type":"duration","value":#{THREE_DAYS}}))]

    assert_equal(%w[depth_limit_exceeded] * 4, too_deep.map { |text| refusal(Tagged.decode(text)) })
  end

  # sabotage: drop the deep call from Writer.container; the value nested
  # past the limit is written and the assert_equal on its refusal fails.
  def test_encode_holds_to_the_same_depth_limit
    at_limit = decoded(nested(Tagged::DEPTH_LIMIT))

    assert_predicate Tagged.encode(at_limit), :ok?
    assert_equal(%w[depth_limit_exceeded] * 2,
                 [[at_limit], wrapped(Tagged::DEPTH_LIMIT - 1, Predicator::Duration.new)]
                   .map { |value| refusal(Tagged.encode(value)) })
  end

  # sabotage: answer result.value in Tagged.unwrap whatever the result;
  # decode! answers nil and the assert_raises fails.
  def test_the_raising_variants_raise_the_codec_error
    raised = assert_raises(Predicator::Error) { Tagged.decode!("{") }

    assert_equal %w[CodecError malformed_json], [raised.error.type, raised.error.reason]
    assert_equal "reserved_map_key", assert_raises(Predicator::Error) { Tagged.encode!({ "$type" => 1 }) }.error.reason
  end
end
