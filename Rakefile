# frozen_string_literal: true

require "minitest/test_task"
require "rubocop/rake_task"
require_relative "test/conformance/corpus_check"
require_relative "test/conformance/ratchet"
require_relative "test/conformance/runner"

RuboCop::RakeTask.new

# The suite runs under SimpleCov (configured in .simplecov), which fails the
# run below the coverage minimum. SimpleCov is required in the prelude, ahead
# of minitest/autorun, so that it reports after the suite has run rather than
# before it.
Minitest::TestTask.create(:test) do |t|
  t.test_prelude = %(require "simplecov")
  t.test_globs = ["test/**/*_test.rb"]
end

# The conformance apparatus under conformance/ (its README says what is
# copied and from where). The code these tasks call lives in
# test/conformance/, beside the suite that tests it; none of it ships.
namespace :corpus do
  desc "Check the vendored corpus and transcripts against their records"
  task :check do
    problems = Conformance::CorpusCheck.problems
    unless problems.empty?
      abort ["corpus:check failed:", *problems, "per-file digests, to find what moved:",
             *Conformance::CorpusCheck.digests, "Restore the copied bytes or vendor a tag; never rewrite a hash."]
        .join("\n  ")
    end
    puts Conformance::CorpusCheck.summary
  end
end

# A stage of the gate: every check conformance/RATCHET.md puts over the
# registry, against a run of both surfaces made now.
desc "Check conformance/registry.json against the corpus and a run made now"
task :registry do
  corpus = Conformance::Corpus.load
  reports = Conformance::Runner.observe(corpus)
  problems = Conformance::RegistryCheck.problems(File.binread(Conformance::Registry::PATH), corpus, reports,
                                                 Conformance::Attempts::ISA_VERSION)
  abort ["registry failed:", *problems].join("\n  ") unless problems.empty?

  entries = JSON.parse(File.read(Conformance::Registry::PATH))["entries"]
  Conformance::SURFACES.each do |surface|
    unentered = Conformance::Registry.unentered(corpus, surface, entries).size
    puts "registry: #{surface}: #{unentered} of #{corpus.surface_set(surface).size} cases without an entry"
  end
end

# Verify-then-add, the only writer of conformance/registry.json: it runs both
# surfaces now and adds what passed. Claims are asserted as task arguments,
# e.g. rake "ratchet[evaluator:2,compiler:1]".
desc "Run both surfaces and add every observed pass to conformance/registry.json"
task :ratchet do |_task, args|
  claims = args.extras.map { |text| Conformance::Ratchet.parse_claim(text) || abort("ratchet: #{text} is not surface:tier") }
  corpus = Conformance::Corpus.load
  problems = Conformance::Ratchet.write(Conformance::Registry::PATH, corpus, Conformance::Runner.observe(corpus),
                                        claims:)
  abort ["ratchet refused; nothing was written:", *problems].join("\n  ") unless problems.empty?

  puts "ratchet: wrote #{Conformance::Registry::PATH.delete_prefix("#{__dir__}/")}"
end

# The publish step of .github/workflows/release.yml, which publishes through
# rubygems/release-gem: that action runs `bundle exec rake release` once it
# has exchanged the run's OIDC identity for a short-lived rubygems.org
# credential (trusted publishing), and afterwards waits for the gem it finds
# under pkg/ to appear on rubygems.org. The task builds the gem into pkg/ and
# pushes it. Unlike Bundler's own release task it never creates or pushes a
# git tag: the workflow runs on the push of the version tag, so the tag
# already exists.
#
# Anywhere but that workflow, on the push of the tag naming
# Predicator::VERSION, it refuses before building anything: a person or an
# agent never publishes from a checkout (CLAUDE.md, "Release preps"). The
# guard is a tripwire against an accidental `rake release`, not a security
# boundary.
module ReleaseTask
  # The repository whose release.yml may publish the gem.
  REPOSITORY = "riddler/predicator-rb"

  # Why the release task must not run under env (the process environment)
  # for the gem at version, or nil when it may: only GitHub Actions, on the
  # push of the tag vVERSION, in REPOSITORY's release.yml.
  def self.refusal(env, version)
    tag = "v#{version}"
    workflow = "#{REPOSITORY}/.github/workflows/release.yml@refs/tags/#{tag}"
    return if env["GITHUB_ACTIONS"] == "true" && env["GITHUB_REPOSITORY"] == REPOSITORY &&
              env["GITHUB_REF"] == "refs/tags/#{tag}" &&
              env["GITHUB_WORKFLOW_REF"] == workflow

    "release: runs only in .github/workflows/release.yml on the push of #{tag}; nothing was built or pushed"
  end
end

desc "Build and push the gem (only inside .github/workflows/release.yml on its version tag)"
task :release do
  require "bundler/gem_helper"

  helper = Bundler::GemHelper.new(__dir__, "predicator")
  refusal = ReleaseTask.refusal(ENV, helper.gemspec.version)
  abort refusal if refusal

  dirty = !system("git", "diff", "--quiet") || !system("git", "diff", "--cached", "--quiet")
  abort "release: the checkout has uncommitted changes; nothing was built or pushed" if dirty

  sh "gem", "push", helper.build_gem
end

# The full gate.
task default: %i[rubocop corpus:check registry test]
