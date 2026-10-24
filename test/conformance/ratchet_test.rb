# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "runner"
require_relative "ratchet"

# What the ratchet tests build their registries and runs from.
module RatchetTestHelper
  CORPUS = Conformance::Corpus.load
  ISA = Conformance::Attempts::ISA_VERSION
  EMPTY = { "claims" => [], "corpus_hash" => CORPUS.corpus_hash, "entries" => [],
            "implementation" => "predicator-rb", "isa_version" => CORPUS.isa_version }.freeze

  def with_registry(registry = EMPTY)
    Dir.mktmpdir("registry") do |dir|
      path = File.join(dir, "registry.json")
      File.binwrite(path, Conformance::Registry.encode(registry))
      yield path
    end
  end

  # Reports in which exactly the cases ids name pass.
  def reports_passing(ids)
    Conformance::Runner.observe(CORPUS, attempts: Conformance::SURFACES.to_h do |surface|
      [surface, ->(item) { ids.include?(item["id"]) ? :pass : "not this one" }]
    end)
  end

  def entry(item, surface) = { "case_id" => item["id"], "surface" => surface, "tier" => item["tier"] }
  def written(path) = JSON.parse(File.binread(path))
  def tier_one(surface) = CORPUS.runnable(surface, ISA).select { |item| item["tier"] == 1 }
  def sorted(entries) = entries.sort_by { |e| Conformance::Registry.entry_order(e) }

  # A case on both surfaces (the compiler's last) and a case on the
  # evaluator's alone.
  def two_cases = [CORPUS.surface_set("compiler").last, CORPUS.cases.find { |item| item["source"].nil? }]

  # A registry claiming evaluator tier 1 with every entry that claim needs.
  def evaluator_tier_one_claimed
    EMPTY.merge("claims" => [{ "surface" => "evaluator", "tier" => 1 }],
                "entries" => tier_one("evaluator").map { |item| entry(item, "evaluator") })
  end
end

# Verify-then-add (Conformance::Ratchet, the rake ratchet task): the only
# writer of the registry, from the reports of a run. Every test drives it
# against a registry in a temporary directory, never the shipped one.
class RatchetTest < Minitest::Test
  include RatchetTestHelper

  # sabotage: make Ratchet.write leave the file as it found it after the
  # problems check; the bytes then still carry the old pin and the
  # assert_equal on the written bytes fails.
  def test_with_nothing_passing_it_writes_the_empty_registry_pinned_to_the_corpus
    with_registry(EMPTY.merge("corpus_hash" => "sha256:#{"1" * 64}")) do |path|
      assert_empty Conformance::Ratchet.write(path, CORPUS, reports_passing([]))
      assert_equal Conformance::Registry.encode(EMPTY), File.binread(path)
    end
  end

  # sabotage: make Ratchet.passes answer {} for every report; no entry is
  # added and the assert_equal on the written entries fails.
  def test_adds_every_observed_pass_on_its_surface_in_order
    both, only = two_cases
    with_registry do |path|
      assert_empty Conformance::Ratchet.write(path, CORPUS, reports_passing([both["id"], only["id"]]))
      assert_equal sorted([entry(both, "compiler"), entry(both, "evaluator"), entry(only, "evaluator")]),
                   written(path)["entries"]
    end
  end

  # sabotage: write JSON.pretty_generate(registry) in Ratchet.write; the
  # assert_equal on the re-encoded bytes fails.
  def test_writes_in_the_one_line_per_entry_encoding
    with_registry do |path|
      Conformance::Ratchet.write(path, CORPUS, reports_passing(two_cases.map { |item| item["id"] }))

      assert_equal 3, written(path)["entries"].size
      assert_equal Conformance::Registry.encode(written(path)), File.binread(path)
    end
  end

  # sabotage: make Ratchet.regressions answer []; the entry is dropped and
  # the assert_equal on the refusal fails.
  def test_refuses_to_write_when_an_entry_no_longer_passes
    item = CORPUS.cases.first
    with_registry(EMPTY.merge("entries" => [entry(item, "evaluator")])) do |path|
      before = File.binread(path)

      assert_equal ["#{item["id"]} on evaluator no longer passes"],
                   Conformance::Ratchet.write(path, CORPUS, reports_passing([]))
      assert_equal before, File.binread(path)
    end
  end

  # sabotage: make Ratchet.merged skip the missing-entry check; the claim is
  # written and the assertion on the refusal fails.
  def test_refuses_a_claim_the_entries_do_not_support
    with_registry do |path|
      problems = Conformance::Ratchet.write(path, CORPUS, reports_passing([]),
                                            claims: [{ "surface" => "compiler", "tier" => 1 }])

      assert_equal CORPUS.surface_set("compiler").count { |item| item["tier"] == 1 }, problems.size
      assert(problems.all? { |line| line.start_with?("the claim compiler:1 wants ") })
      assert_equal Conformance::Registry.encode(EMPTY), File.binread(path)
    end
  end

  # sabotage: replace the claims by the asserted ones in Ratchet.next_registry
  # instead of merging; the carried evaluator claim is dropped and the
  # assert_equal on the written claims fails.
  def test_writes_a_complete_claim_and_carries_the_others_forward
    ids = (tier_one("compiler") + tier_one("evaluator")).map { |item| item["id"] }
    with_registry(evaluator_tier_one_claimed) do |path|
      assert_empty Conformance::Ratchet.write(path, CORPUS, reports_passing(ids),
                                              claims: [Conformance::Ratchet.parse_claim("compiler:1")])
      assert_equal [{ "surface" => "compiler", "tier" => 1 }, { "surface" => "evaluator", "tier" => 1 }],
                   written(path)["claims"]
    end
  end

  # sabotage: make Ratchet.report_problems answer []; the report of another
  # corpus is read and the assertion on the refusal fails.
  def test_refuses_a_report_of_another_corpus
    reports = reports_passing([]).map { |report| report.merge("corpus_hash" => "sha256:#{"2" * 64}") }
    with_registry do |path|
      problems = Conformance::Ratchet.write(path, CORPUS, reports)

      assert_equal 2, problems.size
      assert_match(/\Athe compiler report was run against sha256:2{64}; the vendored manifest pins /, problems.first)
    end
  end

  # sabotage: drop the version test from Ratchet.report_problems; the
  # assert_equal on the refusal fails.
  def test_refuses_reports_that_disagree_about_the_version_claimed
    reports = reports_passing([])
    reports[1] = reports[1].merge("isa_version" => ISA - 1)
    with_registry do |path|
      assert_equal ["the reports disagree about the instruction-set version claimed: #{ISA}, #{ISA - 1}"],
                   Conformance::Ratchet.write(path, CORPUS, reports)
    end
  end

  # sabotage: make Ratchet.passes accept any id; the unknown case is entered
  # and the assert_equal on the refusal fails.
  def test_refuses_a_report_passing_a_case_the_corpus_does_not_hold
    report = reports_passing([]).first
    report = report.merge("results" => [{ "id" => "no/such-case", "result" => "pass" }])
    with_registry do |path|
      assert_equal ["the compiler report passes no/such-case, which the corpus does not hold"],
                   Conformance::Ratchet.write(path, CORPUS, [report])
    end
  end

  # sabotage: drop the \z anchor from Ratchet.parse_claim's pattern; the
  # assert_nil on a trailing word fails.
  def test_reads_a_claim_only_as_surface_and_tier
    assert_equal({ "surface" => "evaluator", "tier" => 9 }, Conformance::Ratchet.parse_claim("evaluator:9"))
    assert_nil Conformance::Ratchet.parse_claim("evaluator:9x")
    assert_nil Conformance::Ratchet.parse_claim("analysis:1")
    assert_nil Conformance::Ratchet.parse_claim("compiler:0")
  end

  # sabotage: make Ratchet.write ignore a registry that does not parse; the
  # assert_equal on the refusal fails.
  def test_refuses_a_registry_file_that_does_not_parse
    with_registry do |path|
      File.binwrite(path, "{")

      assert_match(/\Aregistry.json: the registry is not JSON/,
                   Conformance::Ratchet.write(path, CORPUS, reports_passing([])).first)
    end
  end
end
