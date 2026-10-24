# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"
require "rbconfig"

# The public surface, listed whole: every public constant of Predicator and
# of Predicator::Tagged, every public module method, and the public methods
# each public class defines beyond what Data (or its superclass) gives it.
# An addition or a removal fails here, so the surface changes only on
# purpose. Each entry point is asked of a fresh interpreter, so that what
# the main entry point exposes is read before the codec is loaded.
class SurfaceTest < Minitest::Test
  LIB = File.expand_path("../../lib", __dir__)

  PROBE = <<~PROBE
    BASE = Data.define
    own = lambda do |klass|
      base = klass < Data ? BASE : klass.superclass
      { "class" => (klass.singleton_methods - base.singleton_methods).sort.map(&:to_s),
        "instance" => (klass.public_instance_methods - base.public_instance_methods).sort.map(&:to_s) }
    end
    modules = [Predicator, defined?(Predicator::Tagged) && Predicator::Tagged].compact
    classes = modules.flat_map { |mod| mod.constants.map { |name| mod.const_get(name) } }.grep(Class)
    puts JSON.generate(
      "constants" => modules.to_h { |mod| [mod.name, mod.constants.sort.map(&:to_s)] },
      "module_methods" => modules.to_h { |mod| [mod.name, mod.singleton_methods.sort.map(&:to_s)] },
      "classes" => classes.sort_by(&:name).to_h { |klass| [klass.name, own.call(klass)] }
    )
  PROBE

  ERROR_VALUE = { "class" => [], "instance" => %w[message position reason type] }.freeze

  # What `require "predicator"` exposes.
  MAIN = {
    "constants" => {
      "Predicator" => %w[Date DateTime Duration Error EvaluationError ParseError Position Result TypeMismatchError
                         UNDEFINED UndefinedVariableError VERSION]
    },
    "module_methods" => {
      "Predicator" => %w[compile compile! compile_program compile_program! evaluate evaluate! execute execute!
                         execute_value execute_value! isa_version parse parse! parse_duration parse_duration!]
    },
    "classes" => {
      "Predicator::Date" => { "class" => [], "instance" => %w[day month year] },
      "Predicator::DateTime" => { "class" => ["at"],
                                  "instance" => %w[epoch_seconds hour microsecond minute second to_date] },
      "Predicator::Duration" => { "class" => [],
                                  "instance" => %w[days hours milliseconds minutes months seconds weeks years] },
      "Predicator::Error" => { "class" => [], "instance" => ["error"] },
      "Predicator::EvaluationError" => ERROR_VALUE,
      "Predicator::ParseError" => ERROR_VALUE,
      "Predicator::Position" => { "class" => [], "instance" => %w[column line] },
      "Predicator::Result" => { "class" => %w[failure ok], "instance" => %w[error ok? value] },
      "Predicator::TypeMismatchError" => ERROR_VALUE,
      "Predicator::UndefinedVariableError" => ERROR_VALUE
    }
  }.freeze

  # What `require "predicator/tagged"` adds to it, the tagged entry point.
  TAGGED = {
    "constants" => { "Predicator::Tagged" => ["CodecError"] },
    "module_methods" => { "Predicator::Tagged" => %w[decode decode! encode encode!] },
    "classes" => { "Predicator::Tagged::CodecError" => { "class" => [], "instance" => %w[message reason type] } }
  }.freeze

  def surface(*paths)
    requires = paths.map { |path| %(require "#{path}"\n) }.join
    output, status = Open3.capture2(RbConfig.ruby, "-I", LIB, "-rjson", "-e", requires + PROBE)
    assert_predicate status, :success?
    JSON.parse(output)
  end

  # sabotage: drop `private_constant :Undefined` in values.rb; the main
  # entry point lists Undefined among its constants and the assert_equal
  # fails.
  def test_the_main_entry_point_exposes_exactly_this_surface
    assert_equal MAIN, surface("predicator")
  end

  # sabotage: drop `private_constant :DEPTH_LIMIT` in tagged.rb; the codec
  # lists DEPTH_LIMIT among Tagged's constants and the assert_equal fails.
  def test_the_tagged_entry_point_adds_exactly_the_codec
    expected = {
      "constants" => MAIN["constants"].merge(TAGGED["constants"],
                                             "Predicator" => (MAIN["constants"]["Predicator"] + ["Tagged"]).sort),
      "module_methods" => MAIN["module_methods"].merge(TAGGED["module_methods"]),
      "classes" => MAIN["classes"].merge(TAGGED["classes"])
    }

    assert_equal expected, surface("predicator", "predicator/tagged")
  end

  # sabotage: make Predicator.isa_version answer 5; the assert_equal fails.
  def test_isa_version_is_six
    assert_equal 6, Predicator.isa_version
  end
end
