# frozen_string_literal: true

require "json"
require_relative "../../lib/predicator/tagged"

# The conformance apparatus: the corpus vendored under conformance/, the run
# over it, the corpus check and the registry. It lives under test/ because it
# is not part of the gem: the gemspec ships lib/ alone, and nothing in lib/
# knows the corpus exists. The Rakefile loads these files for its
# corpus:check, registry and ratchet tasks, and the suite loads them for its
# tests.
#
# The contract is the reference's, at the tag conformance/SOURCE.json names:
# its conformance/README.md (the two surfaces, the cumulative tiers, the
# never-skip rule, retired cases) and its conformance/RATCHET.md (the
# registry). conformance/README.md here says where to read them.
module Conformance
  # The directory the vendored corpus lives in.
  ROOT = File.expand_path("../../conformance", __dir__)

  # The two surfaces a case is run on, in codepoint order.
  SURFACES = %w[compiler evaluator].freeze

  # A corpus that does not read: a line of a tier file that is not JSON, or a
  # case whose keys the corpus schema does not allow.
  class CorpusError < StandardError; end

  # The keys a case of a tier file may carry, read out of the vendored
  # schema/corpus.json rather than written here: the keys its `properties`
  # names, the keys it requires, and its `oneOf` (exactly one of
  # expected_result and expected_error). A case outside that shape is refused
  # rather than half-read, so a corpus that grows a key is noticed here the
  # day it is vendored.
  CaseShape = Data.define(:known, :required, :alternatives) do
    def self.from_schema(schema)
      new(known: schema.fetch("properties").keys, required: schema.fetch("required"),
          alternatives: schema.fetch("oneOf", []).map { |branch| branch.fetch("required") })
    end

    # What is wrong with item's keys, one sentence each; empty when nothing is.
    def problems(item)
      id = item["id"].inspect
      unknown = (item.keys - known).map do |key|
        "case #{id} carries the key #{key.inspect}, which schema/corpus.json does not name"
      end
      missing = (required - item.keys).map do |key|
        "case #{id} lacks the key #{key.inspect}, which schema/corpus.json requires"
      end
      unknown + missing + alternative_problems(id, item)
    end

    private

    def alternative_problems(id, item)
      matched = alternatives.count { |keys| (keys - item.keys).empty? }
      return [] if alternatives.empty? || matched == 1

      ["case #{id} carries #{matched} of #{alternatives.map(&:join).join(", ")}; schema/corpus.json wants exactly one"]
    end
  end

  # The vendored corpus: its manifest and every case of every tier the
  # manifest lists, in ascending tier order.
  Corpus = Data.define(:manifest, :cases) do
    # Reads the corpus under dir, refusing (CorpusError) a line that is not
    # JSON and a case outside the schema's shape.
    def self.load(dir = ROOT)
      manifest = JSON.parse(File.read(File.join(dir, "manifest.json")))
      shape = CaseShape.from_schema(JSON.parse(File.read(File.join(dir, "schema", "corpus.json"))))
      tiers = manifest.fetch("tiers").sort_by { |tier| tier.fetch("tier") }
      new(manifest:, cases: tiers.flat_map { |tier| read_tier(File.join(dir, tier.fetch("file")), shape) })
    end

    def self.read_tier(path, shape)
      File.foreach(path).with_index(1).filter_map do |line, number|
        next if line.chomp.empty?

        item = parse_line(line, path, number)
        problems = shape.problems(item)
        raise CorpusError, problems.join("; ") unless problems.empty?

        item
      end
    end

    # Every line is read through the package's own tagged codec
    # (Predicator::Tagged), so a case's context, instructions and expected
    # result arrive as predicator values: a tagged date as a Predicator::Date,
    # {"$type":"undefined"} as Predicator::UNDEFINED, 1.0 as a Float. A line
    # the codec refuses is refused here, naming the codec's reason.
    def self.parse_line(line, path, number)
      result = Predicator::Tagged.decode(line)
      return result.value if result.ok?

      error = result.error
      what = error.reason == "malformed_json" ? "is not JSON" : "does not decode"
      raise CorpusError, "#{File.basename(path)} line #{number} #{what} (#{error.reason}): #{error.message}"
    end

    def corpus_hash = manifest.fetch("corpus_hash")
    def isa_version = manifest.fetch("isa_version")
    def top_tier = manifest.fetch("tiers").map { |tier| tier.fetch("tier") }.max

    # Every case for the evaluator; the cases with a source for the compiler.
    # A case with a null source is absent from the compiler's set, not skipped
    # by it.
    def surface_set(surface)
      case surface
      when "evaluator" then cases
      when "compiler" then cases.reject { |item| item["source"].nil? }
      else raise ArgumentError, "no surface #{surface.inspect}"
      end
    end

    # The cases a run of surface attempts when the package claims the
    # instruction-set version claimed: a case tagged `retired` uses an opcode
    # retired at or below the corpus's version, so a run claiming that version
    # does not attempt it, and a run claiming an earlier one does. It stays a
    # member of the evaluator's set either way.
    def runnable(surface, claimed)
      surface_set(surface).reject { |item| claimed >= isa_version && item["features"].include?("retired") }
    end

    # The id => tier map, for the registry's tier check.
    def tiers_by_id = cases.to_h { |item| [item.fetch("id"), item.fetch("tier")] }
  end
end
