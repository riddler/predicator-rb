# frozen_string_literal: true

require_relative "predicator/version"
require_relative "predicator/values"
require_relative "predicator/errors"
require_relative "predicator/result"
require_relative "predicator/evaluator"

# A safe, non-evaluating condition language for end users.
#
# The value domain is Ruby's own values where they fit - nil (null), true and
# false, Integer and Float (kept apart), String, Array (a list) and Hash with
# String keys (a map) - plus {Predicator::UNDEFINED}, {Predicator::Date},
# {Predicator::DateTime} and {Predicator::Duration}. The codec for the
# conformance corpus's tagged encoding is loaded on its own, with
# `require "predicator/tagged"`.
module Predicator
end
