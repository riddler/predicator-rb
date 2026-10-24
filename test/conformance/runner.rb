# frozen_string_literal: true

require_relative "corpus"
require_relative "attempts"

module Conformance
  # The run: every case a surface attempts, each answered pass or fail, in the
  # shape of the reference's schema/report.json. There is no skip list and no
  # third result.
  module Runner
    # The report of one run of surface over corpus at its top tier (tiers are
    # cumulative, so that is every tier), the package claiming isa_version,
    # each case answered by attempt.
    def self.run(corpus, surface, isa_version:, attempt:)
      results = corpus.runnable(surface, isa_version).map { |item| result_for(item, attempt) }
      { "corpus_hash" => corpus.corpus_hash, "isa_version" => isa_version, "results" => results,
        "surface" => surface, "tier" => corpus.top_tier }
    end

    # One report per surface, from the attempts the seam (Attempts) holds
    # today: the observed run the registry check and the ratchet read.
    def self.observe(corpus, attempts: Attempts::ALL, isa_version: Attempts::ISA_VERSION)
      SURFACES.map { |surface| run(corpus, surface, isa_version:, attempt: attempts.fetch(surface)) }
    end

    def self.result_for(item, attempt)
      answer = attempt.call(item)
      return { "id" => item["id"], "result" => "pass" } if answer == :pass

      { "id" => item["id"], "reason" => answer.to_s, "result" => "fail" }
    rescue StandardError => e
      { "id" => item["id"], "reason" => "raised #{e.class}: #{e.message}", "result" => "fail" }
    end
    private_class_method :result_for
  end
end
