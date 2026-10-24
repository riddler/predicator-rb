# frozen_string_literal: true

module Predicator
  module Evaluator
    # The `compare` opcode's answer for one operator and one pair of values,
    # as the reference's ISA (docs/isa.md, section 5, `compare`) states it.
    #
    # Strict equality is decided first and answers a boolean over every
    # value, undefined and null included. Every other operator propagates:
    # undefined on either side, or a pair whose types do not match, answers
    # undefined, never an error. Null has no type peer, so every non-strict
    # comparison involving it answers undefined too.
    #
    # The module holds no state.
    module Compare
      # The operators `compare` accepts; any other operand is an unknown
      # instruction.
      OPERATORS = %w[GT LT EQ GTE LTE NE STRICT_EQ STRICT_NE].freeze

      # What each ordering operator makes of an order (-1, 0 or 1).
      ORDERED = {
        "GT" => lambda(&:positive?), "LT" => lambda(&:negative?),
        "GTE" => ->(order) { order >= 0 }, "LTE" => ->(order) { order <= 0 }
      }.freeze

      # The type of each kind of value a comparison matches a pair on.
      KINDS = {
        Integer => :number, Float => :number, TrueClass => :boolean, FalseClass => :boolean,
        String => :string, Array => :list, Predicator::Date => :chronological,
        Predicator::DateTime => :chronological, Predicator::Duration => :duration, Hash => :map
      }.freeze

      module_function

      # The comparison of left and right under operator: true, false or
      # {Predicator::UNDEFINED}.
      def call(operator, left, right)
        case operator
        when "STRICT_EQ" then strict?(left, right)
        when "STRICT_NE" then !strict?(left, right)
        else loose(operator, left, right)
        end
      end

      def loose(operator, left, right)
        return UNDEFINED unless peers?(left, right)
        return loose_equal?(left, right, by_instant: false) == (operator == "EQ") if %w[EQ NE].include?(operator)

        order = Order.order(left, right)
        order.nil? ? UNDEFINED : ORDERED.fetch(operator).call(order)
      end

      # The type a comparison matches a pair on: integer and float are one
      # type here, and a date and a datetime are one type. Null and undefined
      # have none.
      def kind(value) = KINDS.fetch(value.class) { KINDS.find { |type, _| value.is_a?(type) }&.last }

      def peers?(left, right) = !kind(left).nil? && kind(left) == kind(right)

      def undefined?(value) = UNDEFINED.equal?(value)

      # Strict equality: the same member of the domain with the same value.
      # It does not bridge integer and float, and a date is never strictly
      # equal to a datetime.
      def strict?(left, right)
        case left
        when Array then right.is_a?(Array) && strict_list?(left, right)
        when Hash then right.is_a?(Hash) && strict_map?(left, right)
        else right.instance_of?(left.class) && left == right
        end
      end

      def strict_list?(left, right) = left.size == right.size && left.zip(right).all? { |a, b| strict?(a, b) }

      def strict_map?(left, right)
        left.size == right.size && left.all? { |key, value| right.key?(key) && strict?(value, right[key]) }
      end

      # Loose equality: numbers by value across integer and float, a date
      # and a datetime by the instant each names. Undefined equals nothing,
      # itself included; null equals only null.
      def loose_equal?(left, right, by_instant:)
        return left.nil? && right.nil? if absent?(left) || absent?(right)

        peers?(left, right) && peers_equal?(left, right, by_instant)
      end

      def peers_equal?(left, right, by_instant)
        case kind(left)
        when :chronological then instant(left) == instant(right)
        when :list then list_equal?(left, right, by_instant)
        when :map then map_equal?(left, right, by_instant)
        else left == right
        end
      end

      def absent?(value) = value.nil? || undefined?(value)

      def list_equal?(left, right, by_instant)
        left.size == right.size && left.zip(right).all? { |a, b| members_equal?(a, b, by_instant) }
      end

      def map_equal?(left, right, by_instant)
        left.size == right.size &&
          left.all? { |key, value| right.key?(key) && members_equal?(value, right[key], by_instant) }
      end

      # Two members of a list or a map: two undefined members are the same
      # member, and a date member and a datetime member differ whatever
      # instants they name, unless by_instant asks for the instant alone.
      def members_equal?(left, right, by_instant)
        return left.equal?(right) if undefined?(left) || undefined?(right)
        return false if !by_instant && date_against_datetime?(left, right)

        loose_equal?(left, right, by_instant:)
      end

      def date_against_datetime?(left, right)
        (left.is_a?(Predicator::Date) && right.is_a?(Predicator::DateTime)) ||
          (left.is_a?(Predicator::DateTime) && right.is_a?(Predicator::Date))
      end

      # A date or a datetime as the instant it names, a date at midnight UTC.
      def instant(value)
        return [value.epoch_seconds, value.microsecond] if value.is_a?(Predicator::DateTime)

        [value.to_days * Civil::SECONDS_PER_DAY, 0]
      end
    end
    private_constant :Compare
  end
end
