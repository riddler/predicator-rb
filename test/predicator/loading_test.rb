# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"

# What each entry point loads, asked of a fresh interpreter.
class LoadingTest < Minitest::Test
  LIB = File.expand_path("../../lib", __dir__)
  PROBE = <<~PROBE
    p [defined?(Predicator::Tagged), defined?(Predicator::Date),
       $LOADED_FEATURES.grep(%r{/lib/predicator}).map { |f| f.split("/lib/").last }.sort]
  PROBE

  def loaded_by(path)
    output, status = Open3.capture2(RbConfig.ruby, "-I", LIB, "-e", %(require "#{path}"\n#{PROBE}))
    assert_predicate status, :success?
    output
  end

  # sabotage: add require_relative "predicator/tagged" to lib/predicator.rb;
  # the assert_equal on what the main entry point loads fails.
  def test_the_codec_loads_on_its_own_and_the_main_entry_point_leaves_it_out
    codec = %w[civil errors result tagged tagged/reader tagged/writer values].map { |f| "predicator/#{f}.rb" }
    main = ["predicator.rb"] + %w[civil errors evaluator evaluator/access evaluator/arithmetic
                                  evaluator/chronology evaluator/compare evaluator/order float_text result values
                                  version]
           .map { |f| "predicator/#{f}.rb" }

    assert_equal %(["constant", "constant", #{codec.inspect}]\n), loaded_by("predicator/tagged")
    assert_equal %([nil, "constant", #{main.inspect}]\n), loaded_by("predicator")
  end
end
