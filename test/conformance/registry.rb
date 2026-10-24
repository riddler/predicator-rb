# frozen_string_literal: true

require "json"
require_relative "corpus"

module Conformance
  # The file conformance/registry.json: the record of which cases this package
  # passes, on which surface, against which corpus. Its contract is the
  # reference's conformance/RATCHET.md at the tag SOURCE.json names: the
  # fields, the order, the one-element-per-line encoding, verify-then-add as
  # the only writer (Ratchet), and the checks (RegistryCheck).
  module Registry
    # The registry this repository ships.
    PATH = File.join(ROOT, "registry.json")

    # The top-level keys, in the codepoint order the encoding writes them.
    KEYS = %w[claims corpus_hash entries implementation isa_version].freeze

    # The order RATCHET.md gives entries: surface, then tier, then case id,
    # each ascending (String comparison in Ruby is by byte, which for UTF-8 is
    # codepoint order).
    def self.entry_order(entry) = [entry["surface"], entry["tier"], entry["case_id"]]

    # The (surface, case id) pair an entry is matched on: never the id alone.
    def self.pair(entry) = [entry["surface"], entry["case_id"]]

    # The bytes registry is required to have on disk. The encoder sorts rather
    # than trusting the order it was handed, so a re-encode comparison catches
    # a reordered file as well as a reflowed one. The one shape RATCHET.md's
    # example does not show, an empty array, keeps its brackets on their own
    # lines with nothing between them.
    def self.encode(registry)
      claims = registry.fetch("claims").sort_by { |claim| claim["surface"] }
      entries = registry.fetch("entries").sort_by { |entry| entry_order(entry) }
      ["{", "#{block("claims", claims)},", "#{scalar(registry, "corpus_hash")},", "#{block("entries", entries)},",
       "#{scalar(registry, "implementation")},", scalar(registry, "isa_version"), "}", ""].join("\n")
    end

    # The parsed registry, or a sentence saying why bytes are not one.
    def self.parse(bytes)
      registry = JSON.parse(bytes)
      return "the registry is not a JSON object" unless registry.is_a?(Hash)
      return "the registry's keys are #{registry.keys.sort.join(", ")}; RATCHET.md's are #{KEYS.join(", ")}" \
        unless registry.keys.sort == KEYS
      return "the registry's claims and entries must be arrays" \
        unless registry["claims"].is_a?(Array) && registry["entries"].is_a?(Array)

      registry
    rescue JSON::ParserError => e
      "the registry is not JSON: #{e.message}"
    end

    # The ids a claim covers that have no entry in entered (a set of pairs):
    # every case of the claim's surface in tiers 1 through its tier, of those a
    # run claiming the instruction-set version claimed attempts.
    def self.missing(corpus, claim, entered, claimed)
      corpus.runnable(claim["surface"], claimed)
            .select { |item| item["tier"] <= claim["tier"].to_i }
            .reject { |item| entered.include?([claim["surface"], item["id"]]) }
            .map { |item| item["id"] }
    end

    # The cases of surface's case set that entries (a registry's entries) do
    # not enter: what the run reports per surface as not yet claimed.
    def self.unentered(corpus, surface, entries)
      entered = entries.select { |entry| entry["surface"] == surface }.to_h { |entry| [entry["case_id"], true] }
      corpus.surface_set(surface).reject { |item| entered.key?(item["id"]) }
    end

    def self.scalar(registry, key) = "#{JSON.generate(key)}: #{JSON.generate(registry.fetch(key))}"

    def self.block(name, elements)
      lines = elements.map { |element| canonical(element) }
      lines.empty? ? "\"#{name}\": [\n]" : "\"#{name}\": [\n#{lines.join(",\n")}\n]"
    end

    def self.canonical(object)
      "{#{object.keys.sort.map { |key| "#{JSON.generate(key)}:#{JSON.generate(object[key])}" }.join(",")}}"
    end

    private_class_method :scalar, :block, :canonical
  end

  # Every check RATCHET.md puts over a registry, run over the file's bytes:
  # the pin (its corpus_hash is the corpus on disk), the order, at most one
  # entry per pair and one claim per surface, membership and its tier
  # sibling, the encoding (re-encoding reproduces the bytes), currency (every
  # entry passes in the run made now) and completeness (a claim of tier N has
  # an entry for every case it covers).
  class RegistryCheck
    CHECKS = %i[pin order duplicates membership encoding currency completeness].freeze

    # One sentence per problem with the registry in bytes, against corpus and
    # the reports of a run made now by a package claiming the instruction-set
    # version claimed; empty when it passes.
    def self.problems(bytes, corpus, reports, claimed)
      registry = Registry.parse(bytes)
      return [registry] if registry.is_a?(String)

      check = new(registry, bytes, corpus, reports, claimed)
      CHECKS.flat_map { |name| check.send(name) }
    end

    def initialize(registry, bytes, corpus, reports, claimed)
      @registry = registry
      @bytes = bytes
      @corpus = corpus
      @reports = reports
      @claimed = claimed
    end

    private

    attr_reader :registry, :corpus, :reports, :claimed

    def entries = registry["entries"]
    def claims = registry["claims"]
    def describe(entry) = "#{entry["case_id"]} on #{entry["surface"]}"

    def pin
      return [] if registry["corpus_hash"] == corpus.corpus_hash

      ["the registry pins #{registry["corpus_hash"]}; the vendored manifest's corpus_hash is #{corpus.corpus_hash}"]
    end

    def order
      problems = entries.each_cons(2).filter_map do |left, right|
        next if (Registry.entry_order(left) <=> Registry.entry_order(right)).to_i <= 0

        "the entries are not sorted: #{describe(left)} comes before #{describe(right)}"
      end
      surfaces = claims.map { |claim| claim["surface"].to_s }
      surfaces == surfaces.sort ? problems : problems + ["the claims are not sorted by surface"]
    end

    def duplicates
      entries.map { |entry| Registry.pair(entry) }.tally.select { |_, count| count > 1 }
             .map { |(surface, id), _| "#{id} on #{surface} is entered twice" } +
        claims.map { |claim| claim["surface"] }.tally.select { |_, count| count > 1 }
              .map { |surface, _| "the #{surface} surface is claimed twice" }
    end

    def membership
      tiers = corpus.tiers_by_id
      entries.filter_map do |entry|
        next "#{describe(entry)} names no surface" unless SURFACES.include?(entry["surface"])
        next "#{describe(entry)} is not in the #{entry["surface"]} surface's case set" unless member?(entry)

        tier_problem(entry, tiers[entry["case_id"]])
      end
    end

    def tier_problem(entry, tier)
      "#{describe(entry)} says tier #{entry["tier"]}; the corpus puts it in tier #{tier}" unless tier == entry["tier"]
    end

    def member?(entry) = corpus.surface_set(entry["surface"]).any? { |item| item["id"] == entry["case_id"] }

    def encoding
      return [] if Registry.encode(registry) == @bytes

      ["the registry's bytes are not what re-encoding it produces; something other than rake ratchet wrote it"]
    end

    def currency
      observed = reports.to_h { |report| [report["surface"], passed(report)] }
      entries.filter_map do |entry|
        passes = observed[entry["surface"]]
        next "nothing ran the #{entry["surface"]} surface, and #{describe(entry)} is entered" if passes.nil?
        next if passes.include?(entry["case_id"])

        "#{describe(entry)} no longer passes"
      end
    end

    def passed(report) = report["results"].select { |result| result["result"] == "pass" }.map { |result| result["id"] }

    def completeness
      entered = Set.new(entries.map { |entry| Registry.pair(entry) })
      claims.flat_map do |claim|
        next ["the claim #{claim.inspect} names no surface"] unless SURFACES.include?(claim["surface"])

        Registry.missing(corpus, claim, entered, claimed).map do |id|
          "the claim #{claim["surface"]}:#{claim["tier"]} wants #{id}, which has no entry"
        end
      end
    end
  end
end
