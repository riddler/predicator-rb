# frozen_string_literal: true

require "test_helper"

class VersionTest < Minitest::Test
  GEMSPEC = File.expand_path("../predicator.gemspec", __dir__)

  # sabotage: change VERSION to "2.0.1"; the assertion on "2.0.0.pre" fails.
  def test_version_is_the_pre_release_of_the_rewrite
    assert_equal "2.0.0.pre", Predicator::VERSION
  end

  # sabotage: make the gemspec read a fixed "0.0.0"; the assertion that the
  # gem version equals Predicator::VERSION fails.
  def test_gemspec_reads_the_version_from_the_version_file
    spec = Gem::Specification.load(GEMSPEC)

    assert_equal Predicator::VERSION, spec.version.to_s
  end

  # sabotage: add spec.add_dependency "json" to the gemspec; the assertion
  # that the runtime dependency list is empty fails.
  def test_gemspec_declares_no_runtime_dependencies
    spec = Gem::Specification.load(GEMSPEC)

    assert_empty spec.runtime_dependencies
  end

  # sabotage: set required_ruby_version to ">= 3.2" in the gemspec; the
  # assertion on the requirement string fails.
  def test_gemspec_requires_ruby_3_3_or_later
    spec = Gem::Specification.load(GEMSPEC)

    assert_equal ">= 3.3", spec.required_ruby_version.to_s
  end
end
