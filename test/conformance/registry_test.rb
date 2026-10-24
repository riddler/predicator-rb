# frozen_string_literal: true

require "test_helper"
require_relative "runner"
require_relative "registry"

# The registry checks (Conformance::RegistryCheck, the rake registry stage of
# the gate). The shipped registry passes them all; every refusal is shown on
# a registry constructed in memory to break one rule, never by editing the
# shipped file.
class RegistryTest < Minitest::Test
  CORPUS = Conformance::Corpus.load
  SHIPPED = File.binread(Conformance::Registry::PATH)
  ISA = Conformance::Attempts::ISA_VERSION

  # A report passing every case of surface the run attempts.
  def passing(surface)
    Conformance::Runner.run(CORPUS, surface, isa_version: ISA, attempt: ->(_item) { :pass })
  end

  # A report failing every case of surface the run attempts.
  def failing(surface) = Conformance::Runner.run(CORPUS, surface, isa_version: ISA, attempt: ->(_item) { "no" })

  def all_passing = Conformance::SURFACES.map { |surface| passing(surface) }

  def entry(item, surface) = { "case_id" => item["id"], "surface" => surface, "tier" => item["tier"] }

  def registry(entries: [], claims: [], corpus_hash: CORPUS.corpus_hash)
    { "claims" => claims, "corpus_hash" => corpus_hash, "entries" => entries,
      "implementation" => "predicator-rb", "isa_version" => CORPUS.isa_version }
  end

  # The problems for a registry, encoded as the ratchet writes it unless
  # bytes are given.
  def problems(subject, bytes: Conformance::Registry.encode(subject), reports: all_passing)
    problems_of(bytes, reports:)
  end

  def problems_of(bytes, reports: all_passing) = Conformance::RegistryCheck.problems(bytes, CORPUS, reports, ISA)

  # The registry encoded as the ratchet writes it, with the lines of the two
  # adjacent elements first and second swapped: the one edit the encoder
  # cannot produce.
  def swapped(subject, first, second)
    one, two = [first, second].map { |element| JSON.generate(element) }
    bytes = Conformance::Registry.encode(subject)
    assert_includes bytes, "#{one},\n#{two}\n"
    bytes.sub("#{one},\n#{two}\n", "#{two},\n#{one}\n")
  end

  def first_cases(count, surface = "evaluator") = CORPUS.surface_set(surface).first(count)

  # sabotage: make the pin check compare against "sha256:" alone; the
  # assert_empty on the shipped registry's problems fails.
  def test_the_shipped_registry_passes_every_check_against_a_run_made_now
    assert_empty Conformance::RegistryCheck.problems(SHIPPED, CORPUS, Conformance::Runner.observe(CORPUS), ISA)
    assert_equal "predicator-rb", JSON.parse(SHIPPED)["implementation"]
  end

  # sabotage: make RegistryCheck#currency answer []; the assert_equal on the
  # problem naming the entry fails.
  def test_refuses_an_entry_that_no_longer_passes
    item = first_cases(1).first
    reports = Conformance::SURFACES.map { |surface| failing(surface) }

    assert_equal ["#{item["id"]} on evaluator no longer passes"],
                 problems(registry(entries: [entry(item, "evaluator")]), reports:)
  end

  # sabotage: make RegistryCheck#currency read every surface's passes from
  # the first report; the assertion that nothing ran the compiler fails.
  def test_refuses_an_entry_on_a_surface_nothing_ran
    item = first_cases(1, "compiler").first

    assert_equal ["nothing ran the compiler surface, and #{item["id"]} on compiler is entered"],
                 problems(registry(entries: [entry(item, "compiler")]), reports: [passing("evaluator")])
  end

  # sabotage: make RegistryCheck#pin answer []; the assert_equal on the pin
  # problem fails.
  def test_refuses_a_pin_that_is_not_the_manifests_hash
    other = "sha256:#{"0" * 64}"

    assert_equal ["the registry pins #{other}; the vendored manifest's corpus_hash is #{CORPUS.corpus_hash}"],
                 problems(registry(corpus_hash: other))
  end

  # sabotage: make RegistryCheck#order answer []; the assert_includes on the
  # sort problem fails (the encoding check still fires, so the test asserts
  # the order check's own sentence).
  def test_refuses_an_entry_list_that_is_not_sorted
    a, b = first_cases(2).map { |item| entry(item, "evaluator") }.sort_by { |e| Conformance::Registry.entry_order(e) }
    bytes = swapped(registry(entries: [a, b]), a, b)

    assert_includes problems_of(bytes),
                    "the entries are not sorted: #{b["case_id"]} on evaluator comes before #{a["case_id"]} on evaluator"
  end

  # sabotage: sort entries by case id before surface in Registry.entry_order;
  # the assertion that a compiler entry precedes an evaluator one fails.
  def test_entries_sort_by_surface_then_tier_then_case_id
    late = CORPUS.surface_set("compiler").max_by { |item| item["tier"] }
    early = CORPUS.cases.min_by { |item| [item["tier"], item["id"]] }
    encoded = Conformance::Registry.encode(registry(entries: [entry(early, "evaluator"), entry(late, "compiler")]))

    assert_operator encoded.index(late["id"]), :<, encoded.index(%("case_id":"#{early["id"]}","surface":"evaluator"))
  end

  # sabotage: make RegistryCheck#order skip the claims; the assertion on the
  # claims sentence fails.
  def test_refuses_claims_not_sorted_by_surface
    claims = [{ "surface" => "compiler", "tier" => 1 }, { "surface" => "evaluator", "tier" => 1 }]

    assert_includes problems_of(swapped(registry(claims:), *claims)), "the claims are not sorted by surface"
  end

  # sabotage: make RegistryCheck#encoding answer []; the assert_equal on the
  # encoding problem fails.
  def test_refuses_a_file_something_other_than_the_ratchet_wrote
    reflowed = JSON.pretty_generate(registry)

    assert_equal ["the registry's bytes are not what re-encoding it produces; " \
                  "something other than rake ratchet wrote it"], problems(registry, bytes: reflowed)
  end

  # sabotage: make RegistryCheck#membership skip the surface-set test; the
  # assertion on the null-source compiler entry fails.
  def test_refuses_a_compiler_entry_for_a_case_with_no_source
    item = CORPUS.cases.find { |c| c["source"].nil? }

    assert_includes problems(registry(entries: [entry(item, "compiler")])),
                    "#{item["id"]} on compiler is not in the compiler surface's case set"
  end

  # sabotage: make RegistryCheck#tier_problem answer nil; the assertion on
  # the tier sentence fails.
  def test_refuses_an_entry_whose_tier_is_not_the_corpus_tier
    item = first_cases(1).first
    wrong = entry(item, "evaluator").merge("tier" => item["tier"] + 1)

    assert_equal ["#{item["id"]} on evaluator says tier #{wrong["tier"]}; " \
                  "the corpus puts it in tier #{item["tier"]}"], problems(registry(entries: [wrong]))
  end

  # sabotage: make RegistryCheck#duplicates answer []; the assertion on the
  # duplicate sentence fails.
  def test_refuses_a_pair_entered_twice
    one = entry(first_cases(1).first, "evaluator")

    assert_includes problems(registry(entries: [one, one])), "#{one["case_id"]} on evaluator is entered twice"
  end

  # sabotage: make RegistryCheck#completeness answer []; the assertion on the
  # missing-entry sentence fails.
  def test_refuses_a_claim_its_entries_do_not_support
    tier_one = CORPUS.surface_set("compiler").select { |item| item["tier"] == 1 }
    entries = tier_one.drop(1).map { |item| entry(item, "compiler") }
    subject = registry(entries:, claims: [{ "surface" => "compiler", "tier" => 1 }])

    assert_equal ["the claim compiler:1 wants #{tier_one.first["id"]}, which has no entry"], problems(subject)
  end

  # sabotage: drop the runnable filter from Registry.missing (use
  # surface_set); the claim then wants the retired cases and the assert_empty
  # fails.
  def test_a_complete_claim_passes_without_the_retired_cases
    entries = CORPUS.runnable("evaluator", ISA).map { |item| entry(item, "evaluator") }
    subject = registry(entries:, claims: [{ "surface" => "evaluator", "tier" => CORPUS.top_tier }])

    assert_empty problems(subject)
  end

  # sabotage: make Registry.parse accept any object; the assert_equal on the
  # keys sentence fails.
  def test_refuses_a_registry_without_the_ratchet_documents_keys
    bytes = JSON.generate(registry.except("implementation"))

    assert_equal ["the registry's keys are claims, corpus_hash, entries, isa_version; " \
                  "RATCHET.md's are claims, corpus_hash, entries, implementation, isa_version"],
                 problems(registry, bytes:)
  end
end
