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

      # Where each kind of member sits in the reference's term order, for a
      # member pair of two different kinds: a number, then false, null, true
      # and undefined, then the map-like values (a map, a duration, a date, a
      # datetime), then a list, then a string.
      MEMBER_RANKS = { number: 0, map: 5, duration: 5, chronological: 5, list: 6, string: 7 }.freeze

      # The rank of each member that is one value of its own kind.
      SINGLE_RANKS = { false => 1, nil => 2, true => 3 }.freeze

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
      #
      # The walk is iterative: a member pair of two lists is walked as a list
      # of its own on an explicit stack of frames (the two lists and the
      # position reached), so lists nested deeper than the stack are ordered
      # rather than exhausting it. Any answer other than level decides the
      # whole order at once. A nested pair that ends level (every member
      # pair level, the sizes equal) is equal by instant, which is what makes
      # a member pair level, so its parent steps to the next position.
      def list_order(left, right)
        frames = [[left, right, 0]]
        until frames.empty?
          step = frame_step(frames)
          return step unless step == LEVEL
        end
        LEVEL
      end

      # One step of the walk over the top frame: LEVEL to go on, else the
      # whole walk's answer.
      def frame_step(frames)
        outer, inner, at = frames.last
        return frame_end(frames) if at == [outer.size, inner.size].min

        frames.last[2] = at + 1
        pair = [outer[at], inner[at]]
        pair.all?(Array) ? descend(frames, pair) : member_order(*pair)
      end

      # Walks a member pair of two lists as a frame of its own.
      def descend(frames, pair)
        frames.push([*pair, 0])
        LEVEL
      end

      # The end of the top frame, its lists ordered by size: that order
      # decides the walk when it is not level or when it is the outermost
      # frame.
      def frame_end(frames)
        outer, inner, = frames.pop
        order = outer.size <=> inner.size
        frames.empty? || !order.zero? ? order : LEVEL
      end

      # One member pair of a list walk: LEVEL when it does not decide, else
      # the order it decides, or nil when it has none. Two members of
      # different kinds are placed by the reference's term order (rank); two
      # nulls, two undefineds, two falses or two trues are level; a date
      # member orders before a datetime member, as term order places them.
      def member_order(left, right)
        ranks = [rank(left), rank(right)]
        return ranks.first <=> ranks.last unless ranks.first == ranks.last
        return LEVEL if (1..4).cover?(ranks.first)
        return left.is_a?(Predicator::Date) ? -1 : 1 if Compare.date_against_datetime?(left, right)
        return LEVEL if Compare.loose_equal?(left, right, by_instant: left.is_a?(Hash) && right.is_a?(Hash))

        differing_order(left, right)
      end

      # A member pair of one kind that is not equal: its order, LEVEL when it
      # orders level and is equal by instant, or nil.
      def differing_order(left, right)
        order = order(left, right)
        return order unless order&.zero?

        Compare.loose_equal?(left, right, by_instant: true) ? LEVEL : nil
      end

      # A member's rank in term order (MEMBER_RANKS, SINGLE_RANKS); undefined
      # ranks 4. A value outside the domain has no rank.
      def rank(member)
        return 4 if Compare.undefined?(member)

        SINGLE_RANKS.fetch(member) { MEMBER_RANKS[Compare.kind(member)] }
      end
    end
    private_constant :Order
  end
end
