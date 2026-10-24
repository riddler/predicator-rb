# frozen_string_literal: true

require_relative "registry"

module Conformance
  # Verify-then-add, RATCHET.md's rule 3: the only writer of the registry.
  #
  # Its only input is the reports of a run; there is no way to add a case by
  # id, so every line the file holds was produced by a run that observed a
  # pass. It never removes an entry: an entry the run did not observe passing
  # is a regression, and it refuses to write, naming each one. A claim it is
  # asked to write must be complete (every case of the surface in tiers 1
  # through N, of those the run attempts, entered), or it refuses that too.
  # Claims it is not asked about are carried forward and re-checked. The file
  # is re-pinned to the vendored manifest's corpus_hash and isa_version.
  module Ratchet
    # Writes the registry at path from reports, adding claims (each
    # {"surface" => ..., "tier" => ...}). Answers the problems that stopped it,
    # having written nothing, or an empty list once the file is written.
    def self.write(path, corpus, reports, claims: [])
      existing = Registry.parse(File.binread(path))
      return ["#{File.basename(path)}: #{existing}"] if existing.is_a?(String)

      registry = report_problems(corpus, reports)
      registry = next_registry(existing, corpus, reports, claims) if registry.empty?
      return registry if registry.is_a?(Array)

      File.binwrite(path, Registry.encode(registry))
      []
    end

    # A claim written as `surface:tier` (as the rake task takes it), or nil
    # when text is not one.
    def self.parse_claim(text)
      match = /\A(compiler|evaluator):([1-9][0-9]*)\z/.match(text.to_s)
      match && { "surface" => match[1], "tier" => Integer(match[2]) }
    end

    def self.report_problems(corpus, reports)
      versions = reports.map { |report| report["isa_version"] }.uniq
      problems = reports.reject { |report| report["corpus_hash"] == corpus.corpus_hash }.map do |report|
        "the #{report["surface"]} report was run against #{report["corpus_hash"]}; " \
          "the vendored manifest pins #{corpus.corpus_hash}"
      end
      return problems if versions.size <= 1

      problems << "the reports disagree about the instruction-set version claimed: #{versions.join(", ")}"
    end

    def self.next_registry(existing, corpus, reports, claims)
      candidates = passes(corpus, reports)
      return candidates if candidates.is_a?(Array)

      regressions = regressions(existing, candidates)
      return regressions unless regressions.empty?

      entries = existing["entries"].to_h { |entry| [Registry.pair(entry), entry] }.merge(candidates)
      merged(existing, corpus, entries.values, by_surface(existing["claims"]).merge(by_surface(claims)),
             claimed_version(corpus, reports))
    end

    # An existing entry no report observed passing is a regression: the
    # answer is to fix the code, never to drop the entry.
    def self.regressions(existing, candidates)
      existing["entries"].reject { |entry| candidates.key?(Registry.pair(entry)) }
                         .map { |entry| "#{entry["case_id"]} on #{entry["surface"]} no longer passes" }
    end

    def self.merged(existing, corpus, entries, claims, claimed)
      entered = Set.new(entries.map { |entry| Registry.pair(entry) })
      missing = claims.values.flat_map do |claim|
        Registry.missing(corpus, claim, entered, claimed).map do |id|
          "the claim #{claim["surface"]}:#{claim["tier"]} wants #{id}, which has no entry"
        end
      end
      return missing unless missing.empty?

      { "claims" => claims.values, "corpus_hash" => corpus.corpus_hash, "entries" => entries,
        "implementation" => existing["implementation"], "isa_version" => corpus.isa_version }
    end

    def self.by_surface(claims) = claims.to_h { |claim| [claim["surface"], claim] }

    # The version the run claimed, which scopes a claim's completeness.
    def self.claimed_version(corpus, reports) = reports.first ? reports.first["isa_version"] : corpus.isa_version

    # The pair => entry map of every pass the reports observed, or the
    # problems when a report passes a case the corpus does not hold.
    def self.passes(corpus, reports)
      tiers = corpus.tiers_by_id
      pairs = reports.flat_map { |report| passed_pairs(report) }
      unknown = pairs.reject { |(_, id)| tiers.key?(id) }
      return unknown.map { |(surface, id)| "the #{surface} report passes #{id}, which the corpus does not hold" } \
        unless unknown.empty?

      pairs.to_h { |surface, id| [[surface, id], { "case_id" => id, "surface" => surface, "tier" => tiers[id] }] }
    end

    def self.passed_pairs(report)
      report["results"].select { |result| result["result"] == "pass" }
                       .map { |result| [report["surface"], result["id"]] }
    end

    private_class_method :report_problems, :next_registry, :regressions, :merged, :by_surface, :claimed_version,
                         :passes, :passed_pairs
  end
end
