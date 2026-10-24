# frozen_string_literal: true

require_relative "evaluator_helper"

# The assertions the cast tests share: one value cast to one type name.
module CastHelper
  include EvaluatorHelper

  def cast(value, type_name)
    result = run_list([["lit", value], ["cast", type_name]])
    assert_predicate result, :ok?, -> { "failed with #{result.error.inspect}" }
    result.value
  end

  def assert_undefined(value, type_name)
    assert_same Predicator::UNDEFINED, cast(value, type_name), "#{value.inspect}::#{type_name}"
  end

  # Asserts each text casts to the value it is paired with.
  def assert_casts(type_name, pairs)
    pairs.each { |text, expected| assert_equal expected, cast(text, type_name), text.inspect }
  end

  def date(year, month, day) = Predicator::Date.new(year:, month:, day:)

  # The instant at "YYYY-MM-DDTHH:MM:SS" in UTC, for a year of four digits.
  def instant(text)
    Predicator::DateTime.at(date(*text[0, 10].split("-").map(&:to_i)), *text[11, 8].split(":").map(&:to_i))
  end

  def duration(**units) = Predicator::Duration.new(**units)
end
