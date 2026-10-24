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

  # What the codec's entry point loads.
  CODEC = %w[civil errors result tagged tagged/reader tagged/writer values].map { |f| "predicator/#{f}.rb" }.freeze

  # What the main entry point loads.
  MAIN = (["predicator.rb"] +
          %w[ast civil duration_text emitter emitter/chains emitter/statements errors evaluator evaluator/access
             evaluator/arithmetic evaluator/calls evaluator/casts evaluator/chronology evaluator/compare
             evaluator/json_functions evaluator/json_scan evaluator/library evaluator/math_functions evaluator/order
             evaluator/rich_types evaluator/statements float_text iso_text lexer lexer/literals lexer/numbers parser
             parser/durations parser/operators parser/postfix parser/primaries parser/statements parser/token_text
             result values version].map { |f| "predicator/#{f}.rb" }).freeze

  def loaded_by(path)
    output, status = Open3.capture2(RbConfig.ruby, "-I", LIB, "-e", %(require "#{path}"\n#{PROBE}))
    assert_predicate status, :success?
    output
  end

  # sabotage: add require_relative "predicator/tagged" to lib/predicator.rb;
  # the assert_equal on what the main entry point loads fails.
  def test_the_codec_loads_on_its_own_and_the_main_entry_point_leaves_it_out
    assert_equal %(["constant", "constant", #{CODEC.inspect}]\n), loaded_by("predicator/tagged")
    assert_equal %([nil, "constant", #{MAIN.inspect}]\n), loaded_by("predicator")
  end
end
