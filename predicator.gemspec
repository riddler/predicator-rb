# frozen_string_literal: true

# The version file is evaluated inside a throwaway module rather than
# required, so that loading the gemspec (Bundler does, in every process the
# gate starts) does not load lib/ before the test run's coverage starts.
version_file = File.join(__dir__, "lib/predicator/version.rb")
version = Module.new.tap { |m| m.module_eval(File.read(version_file), version_file) }::Predicator::VERSION

Gem::Specification.new do |spec|
  spec.name = "predicator"
  spec.version = version
  spec.authors = ["JohnnyT"]
  spec.email = ["ubergeek3141@gmail.com"]

  spec.summary = "A safe, non-evaluating condition language for end users."
  spec.description = <<~DESCRIPTION.tr("\n", " ").strip
    Compiles a condition written as text into stack-machine instructions and
    evaluates it against a context, without evaluating code. Wire-compatible
    with the Elixir reference implementation. No runtime dependencies.
  DESCRIPTION
  spec.homepage = "https://github.com/riddler/predicator-rb"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.glob("lib/**/*.rb", base: __dir__) + %w[README.md CHANGELOG.md LICENSE]
  spec.require_paths = ["lib"]
end
