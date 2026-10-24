# frozen_string_literal: true

require "test_helper"
require "predicator/tagged"
require_relative "corpus"
require_relative "copy_helper"

# The corpus read through the package's tagged codec: every case arrives as
# predicator values, and every value the corpus holds round-trips.
class TaggedCorpusTest < Minitest::Test
  include Conformance::CopyHelper

  CORPUS = Conformance::Corpus.load
  VALUE_KEYS = %w[context expected_result instructions].freeze

  # Every value inside a case's context, expected result and instructions.
  def leaves(value, &)
    case value
    when Array then value.each { |member| leaves(member, &) }
    when Hash then value.each_value { |member| leaves(member, &) }
    else yield value
    end
  end

  # A JSON structure with its maps' keys sorted and every number tagged with
  # its class, so two texts compare equal only when 1 and 1.0 agree too.
  def canonical(json)
    case json
    when Hash then json.sort.map { |key, member| [key, canonical(member)] }
    when Array then json.map { |member| canonical(member) }
    when Numeric then [json.class.name, json]
    else json
    end
  end

  def tier_lines
    CORPUS.manifest["tiers"].flat_map { |tier| File.readlines(File.join(Conformance::ROOT, tier["file"])) }
  end

  def classes_of(item)
    found = []
    VALUE_KEYS.each { |key| leaves(item[key]) { |leaf| found << leaf.class } if item.key?(key) }
    found
  end

  # sabotage: parse the tier lines with JSON.parse in Corpus.parse_line; the
  # cases then hold tag objects as maps and the assertion that a date and an
  # undefined arrive decoded fails.
  def test_the_runner_reads_every_case_through_the_codec
    seen = CORPUS.cases.flat_map { |item| classes_of(item) }.uniq

    [Predicator::Date, Predicator::DateTime, Predicator::Duration, Predicator::UNDEFINED.class, Float, Integer,
     NilClass].each { |kind| assert_includes seen, kind }
    date_case = CORPUS.cases.find { |item| item["id"] == "arithmetic/date-plus-duration" }

    assert_kind_of Predicator::Date, date_case["expected_result"]
  end

  # sabotage: write the duration's milliseconds whatever its value in
  # Writer.duration; the re-encoded cases no longer read back as the
  # corpus's own JSON and the assert_equal fails.
  def test_every_case_round_trips_through_the_codec_as_the_corpus_writes_it
    lines = tier_lines

    assert_equal CORPUS.cases.size, lines.size
    lines.zip(CORPUS.cases).each do |line, item|
      written = JSON.parse(Predicator::Tagged.encode!(item))

      assert_equal canonical(JSON.parse(line)), canonical(written), item["id"]
    end
  end

  # sabotage: answer "is not JSON" for every refusal in Corpus.parse_line;
  # the assert_match on the codec's reason fails.
  def test_a_line_the_codec_refuses_is_refused_naming_the_reason
    with_conformance_copy do |dir|
      rewrite(dir, "corpus/tier-2.json") { |bytes| bytes.sub('"value":"2024-01-15"', '"value":"2024-01-32"') }
      error = assert_raises(Conformance::CorpusError) { Conformance::Corpus.load(dir) }

      assert_match(/\Atier-2.json line \d+ does not decode \(invalid_tagged_value\): /, error.message)
    end
  end
end
