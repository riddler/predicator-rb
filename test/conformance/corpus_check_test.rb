# frozen_string_literal: true

require "test_helper"
require_relative "corpus_check"
require_relative "copy_helper"

# The hash rule over the vendored corpus and the copied transcripts
# (Conformance::CorpusCheck, the rake corpus:check stage of the gate). The
# shipped copies pass; each other test breaks one thing in a throwaway copy
# and asserts the check names the field that disagrees.
class CorpusCheckTest < Minitest::Test
  include Conformance::CopyHelper

  def problems_after(relative, &)
    with_conformance_copy do |dir|
      rewrite(dir, relative, &)
      return Conformance::CorpusCheck.problems(dir)
    end
  end

  # sabotage: append a space to conformance/corpus/tier-9.json; the
  # assert_empty on the shipped copies' problems fails.
  def test_the_shipped_copies_are_the_ones_their_records_name
    assert_empty Conformance::CorpusCheck.problems
  end

  # sabotage: drop the manifest.json entry from hash_problems' map; the
  # assertion that a problem names manifest.json corpus_hash fails.
  def test_a_changed_tier_byte_fails_both_corpus_hashes
    problems = problems_after("corpus/tier-2.json") { |bytes| bytes.sub("arithmetic/", "arithmetiq/") }

    assert(problems.any? { |line| line.start_with?("manifest.json corpus_hash is sha256:ddc5cf82") })
    assert(problems.any? { |line| line.start_with?("SOURCE.json corpus_hash is sha256:ddc5cf82") })
  end

  # sabotage: compare corpus_hash against the manifest's in place of the
  # observed hash in hash_problems; the assertion on the SOURCE.json problem
  # fails (a rewritten SOURCE.json hash then goes unnoticed).
  def test_a_rewritten_source_hash_fails_naming_source_json
    problems = problems_after("SOURCE.json") { |bytes| bytes.sub("sha256:ddc5", "sha256:0dc5") }

    hash = "cf824b06b4899e1bd4166263a1ee07016ff239216e029b9276ac17243975"

    assert_equal ["SOURCE.json corpus_hash is sha256:0dc5#{hash}; the tier files hash to sha256:ddc5#{hash}"], problems
  end

  # sabotage: make count_problems answer [] whatever the counts; the
  # assertion naming tier 1's case_count fails.
  def test_a_tier_file_whose_lines_disagree_with_case_count_is_named
    problems = problems_after("corpus/tier-1.json") { |bytes| bytes.lines.drop(1).join }

    assert_includes problems, "manifest.json tier 1 case_count is 70; corpus/tier-1.json holds 69 lines"
  end

  # sabotage: drop the unended-line test from count_problems; the assertion
  # on the unended line fails.
  def test_a_tier_file_without_its_last_newline_is_named
    problems = problems_after("corpus/tier-6.json", &:chomp)

    assert_includes problems,
                    "manifest.json tier 6 case_count is 9; corpus/tier-6.json holds 8 lines and an unended one"
  end

  # sabotage: make unlisted_tier_files answer []; the assertion naming the
  # extra file fails.
  def test_a_tier_file_the_manifest_does_not_list_is_named
    with_conformance_copy do |dir|
      File.write(File.join(dir, "corpus", "tier-10.json"), "")

      assert_includes Conformance::CorpusCheck.problems(dir),
                      "corpus/tier-10.json is not a tier file manifest.json lists"
    end
  end

  # sabotage: make isa_problems answer []; the assertion on isa_version fails.
  def test_an_isa_version_source_json_disagrees_on_is_named
    problems = problems_after("SOURCE.json") { |bytes| bytes.sub('"isa_version": 6', '"isa_version": 5') }

    assert_equal ["SOURCE.json isa_version is 5; manifest.json isa_version is 6"], problems
  end

  # sabotage: drop the sha test from Records.provenance_problems; the
  # assertion on the SOURCE.json sha fails.
  def test_a_source_record_without_a_commit_is_named
    problems = problems_after("SOURCE.json") { |bytes| bytes.sub("fd7fb0157e5a", "v9.5.0") }

    assert_equal 1, problems.size
    assert_match(/\ASOURCE.json sha is "v9.5.0/, problems.first)
  end

  # sabotage: make TranscriptCheck.file_problems answer [] for every file;
  # the assertion naming VENDORED.json files[compile.json] fails.
  def test_a_changed_transcript_byte_fails_vendored_json_and_its_own_record
    problems = problems_after("transcript/compile.json") { |bytes| bytes.sub('"kind":"compile"', '"kind":"compilE"') }

    assert(problems.any? { |line| line.start_with?("transcript/VENDORED.json files[compile.json] is sha256:c8e29a45") })
    assert(problems.any? { |line| line.start_with?("transcript/compile-SOURCE.json transcript_hash is") })
  end

  # sabotage: skip the -SOURCE.json files in TranscriptCheck.problems'
  # file_problems pass; the assertion naming tokens-SOURCE.json fails.
  def test_a_changed_transcript_record_fails_vendored_json
    problems = problems_after("transcript/tokens-SOURCE.json") { |bytes| bytes.sub('"rows": 111', '"rows": 112') }

    assert(problems.any? { |line| line.start_with?("transcript/VENDORED.json files[tokens-SOURCE.json] is") })
    assert_includes problems, "transcript/tokens-SOURCE.json counts.rows is 112; transcript/tokens.json holds 111"
  end

  # sabotage: drop the transcript_hash row from field_problems; the
  # assertion naming the record's transcript_hash fails.
  def test_a_record_hash_rewritten_to_match_a_changed_file_still_fails_vendored_json
    with_conformance_copy do |dir|
      rewrite(dir, "transcript/tokens.json") { |bytes| bytes.sub("limit > 85", "limit > 86") }
      problems = Conformance::CorpusCheck.problems(dir)

      assert(problems.any? { |line| line.start_with?("transcript/VENDORED.json files[tokens.json] is") })
      assert(problems.any? { |line| line.start_with?("transcript/tokens-SOURCE.json transcript_hash is") })
    end
  end

  # sabotage: make TranscriptCheck.unlisted answer []; the assertion naming
  # the unlisted file fails.
  def test_a_transcript_file_vendored_json_does_not_list_is_named
    with_conformance_copy do |dir|
      File.write(File.join(dir, "transcript", "location.json"), "")

      assert_includes Conformance::CorpusCheck.problems(dir),
                      "transcript/location.json is not a file transcript/VENDORED.json lists"
    end
  end

  # sabotage: make own_record_problems answer [] when the record is not
  # listed; the assertion naming the missing record fails.
  def test_a_transcript_without_its_record_is_named
    problems = problems_after("transcript/VENDORED.json") do |bytes|
      bytes.sub(/^    "compile-SOURCE.json": "[^"]+",\n/, "")
    end

    assert_includes problems, "transcript/compile.json has no record (compile-SOURCE.json) listed beside it"
    assert_includes problems, "transcript/compile-SOURCE.json is not a file transcript/VENDORED.json lists"
  end

  # sabotage: drop the corpus_hash row from field_problems; the assertion on
  # the record's corpus_hash fails.
  def test_a_transcript_record_of_another_corpus_is_named
    problems = problems_after("transcript/compile-SOURCE.json") { |bytes| bytes.sub("sha256:ddc5", "sha256:edc5") }

    assert(problems.any? { |line| line.start_with?("transcript/compile-SOURCE.json corpus_hash is \"sha256:edc5") })
  end
end
