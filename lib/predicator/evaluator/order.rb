# frozen_string_literal: true

module Predicator
  module Evaluator
    # The order of two values for the ordering operators of `compare`, as
    # the reference's ISA (docs/isa.md, section 5, `compare`) states it.
    # Pairs are matched and compared for equality by {Compare}.
    #
    # The module holds no state.
    module Order
      # The answer a list walk gives for a member pair that does not decide
      # the order, so the walk steps to the next position.
      LEVEL = :level

      module_function

      # The order of a type-matched pair (-1, 0 or 1), or nil when the pair
      # has none. Strings order by byte, which for UTF-8 is code point order
      # and no collation. Two maps and two durations have no order: the
      # reference leaves map ordering unspecified for a sibling.
      def order(left, right) = Compare.peers?(left, right) ? peer_order(left, right) : nil

      def peer_order(left, right)
        case Compare.kind(left)
        when :number, :string then left <=> right
        when :boolean then (left ? 1 : 0) <=> (right ? 1 : 0)
        when :chronological then Compare.instant(left) <=> Compare.instant(right)
        when :list then list_order(left, right)
        end
      end

      # Two lists from the front: the first member pair that differs decides,
      # and a proper prefix orders before the longer list.
      def list_order(left, right)
        [left.size, right.size].min.times do |at|
          step = member_order(left[at], right[at])
          return step unless step == LEVEL
        end
        left.size <=> right.size
      end

      # One member pair of a list walk: LEVEL when it does not decide, else
      # the order it decides, or nil when it has none. A null member and a
      # date member against a datetime member are placed as the reference's
      # term order places them.
      def member_order(left, right)
        return null_order(left, right) if left.nil? || right.nil?
        return left.is_a?(Predicator::Date) ? -1 : 1 if Compare.date_against_datetime?(left, right)
        return LEVEL if Compare.loose_equal?(left, right, by_instant: left.is_a?(Hash) && right.is_a?(Hash))

        differing_order(left, right)
      end

      # A member pair that is not equal: its order, LEVEL when it orders
      # level and is equal by instant, or nil.
      def differing_order(left, right)
        order = order(left, right)
        return order unless order&.zero?

        Compare.loose_equal?(left, right, by_instant: true) ? LEVEL : nil
      end

      # A null member orders after a number and after false, and before
      # every other member.
      def null_order(left, right)
        return LEVEL if left.nil? && right.nil?

        left.nil? ? null_against(right) : -null_against(left)
      end

      def null_against(other) = Compare.kind(other) == :number || false.equal?(other) ? 1 : -1
    end
    private_constant :Order
  end
end
