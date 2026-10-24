# frozen_string_literal: true

require "test_helper"
require "predicator/tagged"

# What the codec's tests share.
module TaggedHelper
  Tagged = Predicator::Tagged
  DATE = Predicator::Date.new(2026, 8, 6)
  # The codec's nesting limit, a private constant read here so the tests
  # follow it.
  DEPTH_LIMIT = Tagged.const_get(:DEPTH_LIMIT)
  THREE_DAYS = '{"years":0,"months":0,"weeks":0,"days":3,"hours":0,"minutes":0,"seconds":0}'

  def decoded(text) = Tagged.decode!(text)
  def refusal(result) = result.error&.reason

  # Each value's class beside it, at every level and with maps sorted, so
  # that 1 and 1.0 (equal to ==) compare unequal.
  def typed(value)
    case value
    when Array then value.map { |member| typed(member) }
    when Hash then value.sort.map { |key, member| [key, typed(member)] }
    else [value.class, value]
    end
  end
end
