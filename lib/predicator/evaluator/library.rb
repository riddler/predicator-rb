# frozen_string_literal: true

require_relative "math_functions"
require_relative "json_functions"

module Predicator
  module Evaluator
    # The package's function library: the functions the reference ships as
    # its builtins (its string, list, date, math and JSON functions), by the
    # names a `call` reaches them under, with the counts of arguments each
    # takes. {Calls} looks a name up here after the caller's own functions.
    #
    # Each function is a private method of {Machine} that takes the call's
    # arguments and answers its value, or raises {Calls::Refusal} with the
    # sentence the reference refuses those arguments with. This module holds
    # the string, list and date functions; {MathFunctions} and
    # {JsonFunctions} hold the rest.
    #
    # A string's length and a substring's offsets count grapheme clusters,
    # and `index_of` answers a byte offset into the string's UTF-8, as the
    # reference's own string functions do. `trim` removes the characters
    # with the Unicode White_Space property from both ends.
    module Library
      include MathFunctions
      include JsonFunctions

      # One library function: the counts of arguments it takes and the
      # Machine method that runs it.
      Entry = Data.define(:counts, :handler)

      # The library, by name.
      FUNCTIONS = {
        "len" => [1..1, :string_len], "upper" => [1..1, :string_upper], "lower" => [1..1, :string_lower],
        "trim" => [1..1, :string_trim], "starts_with" => [2..2, :string_starts_with?],
        "ends_with" => [2..2, :string_ends_with?], "substring" => [2..3, :string_substring],
        "index_of" => [2..2, :string_index_of], "concat" => [2..2, :list_concat],
        "Date.year" => [1..1, :date_year], "Date.month" => [1..1, :date_month], "Date.day" => [1..1, :date_day],
        "Date.now" => [0..0, :date_now],
        "Math.pow" => [2..2, :math_pow], "Math.sqrt" => [1..1, :math_sqrt], "Math.abs" => [1..1, :math_abs],
        "Math.floor" => [1..1, :math_floor], "Math.ceil" => [1..1, :math_ceil], "Math.round" => [1..1, :math_round],
        "Math.min" => [2..2, :math_min], "Math.max" => [2..2, :math_max], "Math.random" => [0..0, :math_random],
        "JSON.stringify" => [1..1, :json_stringify], "JSON.parse" => [1..1, :json_parse]
      }.transform_values { |counts, handler| Entry.new(counts:, handler:) }.freeze

      # The ends `trim` removes.
      LEADING_SPACE = /\A\p{White_Space}+/
      TRAILING_SPACE = /\p{White_Space}+\z/
      # What substring says of arguments of the wrong types, with two
      # arguments (true) and with three.
      SUBSTRING_TYPES = {
        true => "substring() expects a string and an integer start index",
        false => "substring() expects a string, an integer start index, and an integer length"
      }.freeze
      private_constant :LEADING_SPACE, :TRAILING_SPACE, :SUBSTRING_TYPES

      private

      def string_len(value) = string_arg("len", value).grapheme_clusters.size
      def string_upper(value) = string_arg("upper", value).upcase
      def string_lower(value) = string_arg("lower", value).downcase
      def string_trim(value) = string_arg("trim", value).sub(LEADING_SPACE, "").sub(TRAILING_SPACE, "")

      def string_arg(name, value)
        return value if value.is_a?(String)

        raise Calls::Refusal, "#{name}() expects a string argument"
      end

      def string_starts_with?(value, prefix) = two_strings("starts_with", value, prefix).start_with?(prefix)
      def string_ends_with?(value, suffix) = two_strings("ends_with", value, suffix).end_with?(suffix)
      def string_index_of(value, sub) = two_strings("index_of", value, sub).byteindex(sub) || -1

      def two_strings(name, value, other)
        return value if value.is_a?(String) && other.is_a?(String)

        raise Calls::Refusal, "#{name}() expects two string arguments"
      end

      # The grapheme clusters from start, all of them or length of them. A
      # start or a length past the end answers what the string has. The
      # call's shape is its count of arguments, so a third argument of null
      # is a length that is not an Integer, not a missing one.
      def string_substring(value, start, *length)
        two = length.empty?
        substring_types(value, start, length, two)
        substring_signs(start, length.first, two)
        clusters = value.grapheme_clusters
        (clusters[start, two ? clusters.size : length.first] || []).join
      end

      def substring_types(value, start, length, two)
        return if value.is_a?(String) && start.is_a?(Integer) && length.all?(Integer)

        raise Calls::Refusal, SUBSTRING_TYPES.fetch(two)
      end

      def substring_signs(start, length, two)
        return unless start.negative? || (!two && length.negative?)

        raise Calls::Refusal, "substring() expects a non-negative start index#{" and length" unless two}"
      end

      def list_concat(left, right)
        return left + right if left.is_a?(Array) && right.is_a?(Array)

        raise Calls::Refusal, "concat() expects two list arguments"
      end

      def date_year(value) = civil_date("Date.year", value).year
      def date_month(value) = civil_date("Date.month", value).month
      def date_day(value) = civil_date("Date.day", value).day

      # The date a date names, or the date in UTC an instant falls on.
      def civil_date(name, value)
        return value if value.is_a?(Predicator::Date)
        return value.to_date if value.is_a?(Predicator::DateTime)

        raise Calls::Refusal, "#{name}() expects a date or datetime argument"
      end

      # The current time of this evaluation: the clock the caller passed,
      # read at most once per evaluation, as relative_date reads it.
      def date_now = now
    end
    private_constant :Library
  end
end
