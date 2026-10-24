# frozen_string_literal: true

require "digest"
require "json"

module Conformance
  # Reading the records the checks compare against.
  module Records
    def self.read(dir, relative) = JSON.parse(File.read(File.join(dir, relative)))
    def self.sha256(bytes) = "sha256:#{Digest::SHA256.hexdigest(bytes)}"

    # What is wrong with a vendoring record's repo, tag and sha (the commit
    # the tag resolved to), one sentence each.
    def self.provenance_problems(name, record)
      names = %w[repo tag].filter_map do |key|
        "#{name} #{key} is #{record[key].inspect}, not a name" unless record[key].is_a?(String) && !record[key].empty?
      end
      return names if record["sha"].is_a?(String) && record["sha"].match?(/\A[0-9a-f]{40}\z/)

      names << "#{name} sha is #{record["sha"].inspect}, not a commit"
    end
  end

  # The transcripts copied under conformance/transcript/ are the ones
  # transcript/VENDORED.json records: each file's SHA-256 equals the one
  # VENDORED.json lists for it, every file in the directory is listed, and
  # each transcript's own record (`<name>-SOURCE.json`, copied beside it)
  # carries the same hash in its transcript_hash, the vendored corpus's hash
  # in its corpus_hash, and the file's line count in its counts.rows.
  module TranscriptCheck
    VENDORED = "transcript/VENDORED.json"

    # Every disagreement, one sentence each, naming the field.
    def self.problems(dir, manifest)
      vendored = Records.read(dir, VENDORED)
      files = vendored["files"]
      return ["#{VENDORED} files is not an object of name => sha256"] unless files.is_a?(Hash)

      Records.provenance_problems(VENDORED, vendored) + unlisted(dir, files) +
        files.flat_map { |name, recorded| file_problems(dir, name, recorded) } +
        files.keys.reject { |name| name.end_with?("-SOURCE.json") }
             .flat_map { |name| own_record_problems(dir, name, files, manifest) }
    end

    def self.unlisted(dir, files)
      (Dir.children(File.join(dir, "transcript")).sort - ["VENDORED.json"] - files.keys).map do |name|
        "transcript/#{name} is not a file #{VENDORED} lists"
      end
    end

    def self.file_problems(dir, name, recorded)
      path = File.join(dir, "transcript", name)
      return ["transcript/#{name} is missing, and #{VENDORED} lists it"] unless File.file?(path)

      observed = Records.sha256(File.binread(path))
      return [] if recorded == observed

      ["#{VENDORED} files[#{name}] is #{recorded}; transcript/#{name} hashes to #{observed}"]
    end

    def self.own_record_problems(dir, name, files, manifest)
      record_name = name.sub(/\.json\z/, "-SOURCE.json")
      return ["transcript/#{name} has no record (#{record_name}) listed beside it"] unless files.key?(record_name)

      paths = [name, record_name].map { |file| File.join(dir, "transcript", file) }
      return [] unless paths.all? { |path| File.file?(path) }

      field_problems(record_name, Records.read(dir, "transcript/#{record_name}"), name,
                     File.binread(paths.first), manifest)
    end

    def self.field_problems(record_name, record, name, bytes, manifest)
      [
        ["transcript_hash", record["transcript_hash"], Records.sha256(bytes), "transcript/#{name} hashes to"],
        ["corpus_hash", record["corpus_hash"], manifest["corpus_hash"], "manifest.json corpus_hash is"],
        ["counts.rows", record.dig("counts", "rows"), bytes.count("\n"), "transcript/#{name} holds"]
      ].filter_map do |field, have, want, what|
        "transcript/#{record_name} #{field} is #{have.inspect}; #{what} #{want.inspect}" unless have == want
      end
    end

    private_class_method :unlisted, :file_problems, :own_record_problems, :field_problems
  end
end
