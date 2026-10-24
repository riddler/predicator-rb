# frozen_string_literal: true

# SimpleCov starts before lib/ is loaded, or the loaded lines go uncounted.
# Under `rake test` the task's prelude has already required it; this line
# covers a test file run on its own.
require "simplecov"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "predicator"

require "minitest/autorun"

# The calendar module is private to the package; the tests that build an
# instant from a date and a time of day, or read an instant's date, reach
# it by name.
CIVIL = Predicator.const_get(:Civil)
