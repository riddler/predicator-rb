# frozen_string_literal: true

require "test_helper"
require "rake"

# The Rakefile's `release` task is the publish step of the release workflow,
# and it must refuse everywhere but that workflow on the push of the tag
# naming Predicator::VERSION. The Rakefile is loaded into a throwaway Rake
# application and its guard, ReleaseTask.refusal, is asked about each
# environment; the task itself is never run here.
class ReleaseTaskTest < Minitest::Test
  RAKEFILE = File.expand_path("../Rakefile", __dir__)
  Rake.with_application(Rake::Application.new) { load RAKEFILE }

  VERSION = Predicator::VERSION
  TAG = "v#{VERSION}".freeze
  REPOSITORY = "riddler/predicator-rb"

  # The variables GitHub Actions sets for release.yml on the push of tag.
  def release_workflow(tag)
    {
      "GITHUB_ACTIONS" => "true",
      "GITHUB_REF" => "refs/tags/#{tag}",
      "GITHUB_REPOSITORY" => REPOSITORY,
      "GITHUB_WORKFLOW_REF" => "#{REPOSITORY}/.github/workflows/release.yml@refs/tags/#{tag}"
    }
  end

  def assert_refused(env)
    refusal = ReleaseTask.refusal(env, VERSION)

    assert_equal "release: runs only in .github/workflows/release.yml on the push of #{TAG}; " \
                 "nothing was built or pushed", refusal
  end

  # sabotage: make the guard return nil whatever the environment; the
  # assert_equal on the refusal message fails (nil is not the message).
  def test_refuses_outside_github_actions
    assert_refused({})
  end

  # sabotage: drop the GITHUB_ACTIONS comparison from the guard; the
  # assert_equal on the refusal message fails.
  def test_refuses_without_github_actions_set_even_with_the_workflow_refs
    env = release_workflow(TAG)
    env.delete("GITHUB_ACTIONS")

    assert_refused(env)
  end

  # sabotage: drop the GITHUB_WORKFLOW_REF comparison from the guard; the
  # assert_equal on the refusal message fails.
  def test_refuses_another_workflow_on_the_version_tag
    env = release_workflow(TAG)
    env["GITHUB_WORKFLOW_REF"] = "#{REPOSITORY}/.github/workflows/ci.yml@refs/tags/#{TAG}"

    assert_refused(env)
  end

  # sabotage: drop the GITHUB_REF comparison from the guard; the
  # assert_equal on the refusal message fails.
  def test_refuses_a_tag_that_does_not_name_the_version
    env = release_workflow(TAG)
    env["GITHUB_REF"] = "refs/tags/v#{VERSION}9"

    assert_refused(env)
  end

  # sabotage: drop the GITHUB_REPOSITORY comparison from the guard; the
  # assert_equal on the refusal message fails.
  def test_refuses_with_github_repository_unset
    env = release_workflow(TAG)
    env.delete("GITHUB_REPOSITORY")

    assert_refused(env)
  end

  # sabotage: compare GITHUB_ACTIONS against "1" rather than "true"; the
  # assert_nil on the guard's answer fails (it returns the message).
  def test_allows_release_yml_on_the_version_tag
    assert_nil ReleaseTask.refusal(release_workflow(TAG), VERSION)
  end
end
