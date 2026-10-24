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
      # equal to a datetime. The walk is iterative, so a pair nested deeper
      # than the stack is compared rather than exhausting it; two lists or
      # maps that are one object are equal without a walk.
      def strict?(left, right)
        pairs = [[left, right]]
        until pairs.empty?
          a, b = pairs.pop
          return false unless strict_pair?(a, b) { |member, other| pairs.push([member, other]) }
        end
        true
      end

      # One pair of a strict walk: false when it differs, else true, having
      # handed each member pair of two lists or two maps to the block.
      def strict_pair?(left, right, &)
        return right.instance_of?(left.class) && left == right unless container?(left)
        return true if left.equal?(right)

        right.is_a?(left.is_a?(Array) ? Array : Hash) && left.size == right.size && queued(left, right, &)
      end

      # Hands each member pair of two lists of one size, or of two maps of
      # one size, to the block; false when a key of the left map is missing
      # from the right.
      def queued(left, right)
        if left.is_a?(Array)
          left.each_index { |at| yield(left[at], right[at]) }
          return true
        end

        left.all? { |key, member| right.key?(key) && (yield(member, right[key]) || true) }
      end

      def container?(value) = value.is_a?(Array) || value.is_a?(Hash)

      # Loose equality: numbers by value across integer and float, a date
      # and a datetime by the instant each names. Undefined equals nothing,
      # itself included; null equals only null. Two members of a list or a
      # map follow the member rule (member_pair?). The walk is iterative, as
      # strict? is.
      def loose_equal?(left, right, by_instant:)
        pairs = [[left, right, false]]
        until pairs.empty?
          a, b, member = pairs.pop
          return false unless loose_pair?(a, b, member, by_instant) { |x, y| pairs.push([x, y, true]) }
        end
        true
      end

      # One pair of a loose walk: false when it differs, else true, having
      # handed each member pair of two lists or two maps to the block.
      def loose_pair?(left, right, member, by_instant, &)
        verdict = member_rule(left, right, by_instant) if member
        return verdict unless verdict.nil?
        return left.nil? && right.nil? if absent?(left) || absent?(right)

        peers?(left, right) && peers_equal?(left, right, &)
      end

      # Two values of one type: equal, or their member pairs handed to the
      # block.
      def peers_equal?(left, right, &)
        return instant(left) == instant(right) if kind(left) == :chronological
        return left == right unless container?(left)

        left.equal?(right) || (left.size == right.size && queued(left, right, &))
      end

      # The member rule, or nil when it does not decide: two undefined
      # members are the same member, and a date member and a datetime member
      # differ whatever instants they name, unless by_instant asks for the
      # instant alone.
      def member_rule(left, right, by_instant)
        return left.equal?(right) if undefined?(left) || undefined?(right)

        false if !by_instant && date_against_datetime?(left, right)
      end

      def absent?(value) = value.nil? || undefined?(value)

      def date_against_datetime?(left, right)
        (left.is_a?(Predicator::Date) && right.is_a?(Predicator::DateTime)) ||
          (left.is_a?(Predicator::DateTime) && right.is_a?(Predicator::Date))
      end

      # A date or a datetime as the instant it names, a date at midnight UTC.
      def instant(value)
        return [value.epoch_seconds, value.microsecond] if value.is_a?(Predicator::DateTime)

        [Civil.days_of(value) * Civil::SECONDS_PER_DAY, 0]
      end
    end
    private_constant :Compare
  end
end
