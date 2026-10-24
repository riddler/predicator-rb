# frozen_string_literal: true

require "test_helper"
require_relative "runner"
require_relative "registry"
require_relative "copy_helper"
require_relative "transcript_check"

# The conformance runner: every case of every tier the vendored manifest
# lists, on the evaluator surface and, when its source is not null, on the
# compiler surface, with no skip list. The library is reached only through
# Conformance::Attempts (the seam the evaluator and the compiler are
# plugged into), and the run reports per surface how many cases have no
# registry entry.
class RunnerTest < Minitest::Test
  include Conformance::CopyHelper

  CORPUS = Conformance::Corpus.load
  CASES = CORPUS.cases
  ISA = Conformance::Attempts::ISA_VERSION

  def manifest_case_count = CORPUS.manifest["tiers"].sum { |tier| tier["case_count"] }
  def size_of(surface) = CORPUS.surface_set(surface).size
  def ids(items) = items.map { |item| item["id"] }
  def unentered(surface, entries) = Conformance::Registry.unentered(CORPUS, surface, entries).size

  def print_unentered(entries)
    Conformance::SURFACES.each do |surface|
      puts "conformance: #{surface}: #{unentered(surface, entries)} of #{size_of(surface)} cases without an entry"
    end
  end

  # sabotage: make Corpus.load read only the first tier the manifest lists;
  # the assert_equal on the manifest's total case count fails.
  def test_reads_every_case_of_every_tier
    assert_equal manifest_case_count, CORPUS.cases.size
    assert_equal CORPUS.cases.size, CORPUS.cases.map { |item| item["id"] }.uniq.size
  end

  # sabotage: make surface_set("compiler") answer every case; the
  # assert_equal on the count of cases with a source fails.
  def test_the_compiler_surface_is_the_cases_with_a_source
    with_source = CASES.reject { |item| item["source"].nil? }.size

    assert_equal with_source, size_of("compiler")
    assert_equal CASES.size, size_of("evaluator")
    assert_operator with_source, :<, CASES.size
  end

  # sabotage: filter retired cases in Corpus#runnable whatever the claimed
  # version; the assertion that a run claiming an earlier version attempts
  # every case fails.
  def test_a_retired_case_is_attempted_only_by_a_run_claiming_an_earlier_version
    retired = CASES.count { |item| item["features"].include?("retired") }
    version = CORPUS.isa_version

    assert_operator retired, :>, 0
    assert_equal CASES.size - retired, CORPUS.runnable("evaluator", version).size
    assert_equal CASES.size, CORPUS.runnable("evaluator", version - 1).size
  end

  # sabotage: make Runner.run drop every failing result; the assertion that
  # each attempted case has a result fails.
  def test_every_attempted_case_is_answered_pass_or_fail_with_no_skip
    Conformance::Runner.observe(CORPUS).each do |report|
      assert_equal ids(CORPUS.runnable(report["surface"], ISA)), ids(report["results"])
      report["results"].each { |result| assert_answered(result) }
    end
  end

  def assert_answered(result)
    assert_includes %w[pass fail], result["result"]
    refute_empty result["reason"] unless result["result"] == "pass"
  end

  # sabotage: drop "tier" from the report Runner.run builds; the assert_equal
  # on the report's keys fails.
  def test_a_report_has_the_shape_of_the_corpus_report_schema
    required = Conformance::Records.read(Conformance::ROOT, "schema/report.json")["required"]
    report = Conformance::Runner.run(CORPUS, "compiler", isa_version: 6, attempt: ->(_item) { :pass })
    first = report["results"].first

    assert_equal required.sort, report.keys.sort
    assert_equal [CORPUS.corpus_hash, CORPUS.top_tier], report.values_at("corpus_hash", "tier")
    assert_equal({ "id" => first["id"], "result" => "pass" }, first)
  end

  # sabotage: treat any truthy answer as a pass in Runner.result_for; the
  # assertion that a non-:pass answer fails the case fails.
  def test_only_pass_is_a_pass
    report = Conformance::Runner.run(CORPUS, "evaluator", isa_version: 6, attempt: ->(_item) { true })

    assert(report["results"].all? { |result| result["result"] == "fail" && result["reason"] == "true" })
  end

  # sabotage: drop the rescue from Runner.result_for; the run raises instead
  # of answering a fail naming the exception.
  def test_an_attempt_that_raises_is_a_fail_not_an_abort
    report = Conformance::Runner.run(CORPUS, "compiler", isa_version: 6, attempt: ->(_item) { raise "no parser" })

    assert_equal CORPUS.surface_set("compiler").size, report["results"].size
    assert_equal "raised RuntimeError: no parser", report["results"].first["reason"]
  end

  # sabotage: drop the unknown-key half of CaseShape#problems; Corpus.load
  # reads the copy without raising and assert_raises fails.
  def test_a_case_carrying_a_key_the_schema_does_not_name_is_refused
    with_conformance_copy do |dir|
      rewrite(dir, "corpus/tier-3.json") { |bytes| bytes.sub('{"context"', '{"skip":true,"context"') }
      error = assert_raises(Conformance::CorpusError) { Conformance::Corpus.load(dir) }

      assert_match(%r{carries the key "skip", which schema/corpus.json does not name}, error.message)
    end
  end

  # sabotage: drop the required-key half of CaseShape#problems; the
  # assert_raises on a case without features fails.
  def test_a_case_missing_a_required_key_is_refused
    with_conformance_copy do |dir|
      rewrite(dir, "corpus/tier-1.json") { |bytes| bytes.sub(/"features":\[[^\]]*\],/, "") }
      error = assert_raises(Conformance::CorpusError) { Conformance::Corpus.load(dir) }

      assert_match(%r{lacks the key "features", which schema/corpus.json requires}, error.message)
    end
  end

  # sabotage: make alternative_problems answer []; the assert_raises on a
  # case carrying both expected_result and expected_error fails.
  def test_a_case_with_both_expectations_is_refused
    with_conformance_copy do |dir|
      rewrite(dir, "corpus/tier-1.json") do |bytes|
        bytes.sub('"expected_result":', '"expected_error":{},"expected_result":')
      end
      error = assert_raises(Conformance::CorpusError) { Conformance::Corpus.load(dir) }

      assert_match(%r{carries 2 of expected_result, expected_error; schema/corpus.json wants exactly one},
                   error.message)
    end
  end

  # sabotage: drop the JSON::ParserError rescue from Corpus.parse_line; the
  # error raised is not a CorpusError and assert_raises fails.
  def test_a_line_that_is_not_json_is_refused_naming_it
    with_conformance_copy do |dir|
      rewrite(dir, "corpus/tier-9.json") { |bytes| "#{bytes}{not json\n" }
      error = assert_raises(Conformance::CorpusError) { Conformance::Corpus.load(dir) }

      assert_match(/\Atier-9.json line 7 is not JSON/, error.message)
    end
  end

  # The per-surface report the acceptance asks for: how many of each
  # surface's cases have no registry entry yet. Printed, never failed.
  #
  # sabotage: drop the surface filter from Registry.unentered; with an entry
  # on the evaluator surface only, the assert_equal on the compiler surface
  # fails. (Asserted over a constructed entry list, so it holds whatever the
  # shipped registry enters.)
  def test_reports_per_surface_the_cases_without_a_registry_entry
    print_unentered(JSON.parse(File.read(Conformance::Registry::PATH))["entries"])
    one = [{ "case_id" => CORPUS.surface_set("compiler").first["id"], "surface" => "evaluator", "tier" => 1 }]

    assert_equal size_of("compiler"), unentered("compiler", one)
    assert_equal CASES.size - 1, unentered("evaluator", one)
  end
end
