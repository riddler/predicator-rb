# frozen_string_literal: true

require "digest"
require "json"
require_relative "corpus"
require_relative "transcript_check"

module Conformance
  # The hash rule over the vendored copies: the corpus is the one
  # conformance/SOURCE.json says it is, and each transcript file is the one
  # its records say it is (TranscriptCheck).
  #
  # The corpus hash is the SHA-256 of the tier files' bytes, concatenated in
  # ascending tier order, written `sha256:` and lowercase hex; it must equal
  # the manifest's corpus_hash and SOURCE.json's, and each tier file must hold
  # its tier's case_count lines.
  #
  # A mismatch names the field that disagrees. It is never repaired by
  # rewriting a hash: the hash is what a claim of conformance is anchored to,
  # and a hash rewritten to match whatever is on disk anchors it to nothing.
  # The fix is to restore the copied bytes, or to vendor a new tag and
  # re-record it (conformance/README.md).
  module CorpusCheck
    # Every disagreement under dir, one sentence each; empty when the copies
    # are the ones their records name.
    def self.problems(dir = ROOT)
      manifest = Records.read(dir, "manifest.json")
      corpus_problems(dir, manifest) + TranscriptCheck.problems(dir, manifest)
    end

    # The line the task prints when there is nothing to report.
    def self.summary(dir = ROOT)
      source = Records.read(dir, "SOURCE.json")
      vendored = Records.read(dir, "transcript/VENDORED.json")
      manifest = Records.read(dir, "manifest.json")
      cases = manifest["tiers"].sum { |tier| tier["case_count"] }
      "corpus:check: #{source["repo"]} at #{source["tag"]}, ISA version #{manifest["isa_version"]}, " \
        "#{cases} cases, #{manifest["corpus_hash"]}; transcripts from #{vendored["repo"]} at #{vendored["tag"]}"
    end

    # Each tier file's own digest and line count, for finding which one moved
    # when the concatenated hash disagrees (the hash alone cannot say).
    def self.digests(dir = ROOT)
      tiers(Records.read(dir, "manifest.json")).map do |tier|
        path = File.join(dir, tier["file"])
        next "#{tier["file"]} is missing" unless File.file?(path)

        bytes = File.binread(path)
        "#{tier["file"]} #{Records.sha256(bytes)} #{bytes.count("\n")} lines"
      end
    end

    def self.tiers(manifest) = manifest.fetch("tiers").sort_by { |tier| tier.fetch("tier") }

    def self.corpus_problems(dir, manifest)
      listed = tiers(manifest)
      missing = missing_tier_files(dir, listed)
      return missing unless missing.empty?

      bytes = listed.map { |tier| File.binread(File.join(dir, tier["file"])) }
      count_problems(listed, bytes) + unlisted_tier_files(dir, listed) +
        hash_problems(dir, manifest, Records.sha256(bytes.join))
    end

    def self.missing_tier_files(dir, tiers)
      tiers.map { |tier| tier["file"] }.reject { |file| File.file?(File.join(dir, file)) }
           .map { |file| "#{file} is missing, and manifest.json lists it" }
    end

    def self.count_problems(tiers, bytes)
      tiers.zip(bytes).filter_map do |tier, content|
        lines = content.count("\n")
        complete = content.empty? || content.end_with?("\n")
        next if complete && lines == tier["case_count"]

        "manifest.json tier #{tier["tier"]} case_count is #{tier["case_count"]}; #{tier["file"]} holds " \
          "#{lines} lines#{" and an unended one" unless complete}"
      end
    end

    def self.unlisted_tier_files(dir, tiers)
      listed = tiers.map { |tier| tier["file"] }
      Dir.children(File.join(dir, "corpus")).sort.filter_map do |name|
        "corpus/#{name} is not a tier file manifest.json lists" unless listed.include?("corpus/#{name}")
      end
    end

    def self.hash_problems(dir, manifest, observed)
      source = Records.read(dir, "SOURCE.json")
      hashes = { "manifest.json" => manifest, "SOURCE.json" => source }.filter_map do |name, record|
        next if record["corpus_hash"] == observed

        "#{name} corpus_hash is #{record["corpus_hash"]}; the tier files hash to #{observed}"
      end
      hashes + Records.provenance_problems("SOURCE.json", source) + isa_problems(source, manifest)
    end

    def self.isa_problems(source, manifest)
      return [] if source["isa_version"] == manifest["isa_version"]

      ["SOURCE.json isa_version is #{source["isa_version"].inspect}; " \
       "manifest.json isa_version is #{manifest["isa_version"].inspect}"]
    end

    private_class_method :tiers, :corpus_problems, :missing_tier_files, :count_problems, :unlisted_tier_files,
                         :hash_problems, :isa_problems
  end
end
