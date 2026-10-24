# frozen_string_literal: true

module Predicator
  module Evaluator
    # Member and index access, membership and list construction, as the
    # reference's ISA (docs/isa.md, section 5) states them: the handlers
    # {Machine} runs for `access`, `bracket_access`, `in`, `contains` and
    # `make_list`, and the rules they read through.
    #
    # A duration reads as the map its shape is, as the reference's ISA
    # (section 3) makes it normative: each of its eight unit names answers
    # that unit, and any other key misses. A duration is one value wherever
    # it came from, a literal, an opcode or the host.
    module Access
      # The keys a duration answers.
      DURATION_UNITS = %w[years months weeks days hours minutes seconds milliseconds].freeze

      # The one-of-a-kind values a map key may be besides a String and an
      # Integer: the reference admits its atoms, which are these.
      ATOM_KEYS = [true, false, nil, UNDEFINED].freeze

      # The plain map a duration is: each of its eight unit names to that
      # unit.
      def self.units(duration) = DURATION_UNITS.to_h { |name| [name, duration.public_send(name)] }

      private

      # Reads the named member off the popped target. A miss, and a target
      # that is not a map or a duration, the null value included, answer
      # undefined: access never fails but on an empty stack.
      def access(at, property)
        return insufficient("access") if @stack.empty?

        push(at, member(@stack.pop, property))
      end

      # Pops the key, then the target. A list takes a non-negative Integer and
      # misses past either end; any other key is a type mismatch. A map, a
      # duration, a date or a datetime (each a map in the reference) takes a
      # String, an Integer, a boolean, null or undefined and misses on a key it
      # does not hold; any other key is a type mismatch. Any other target
      # answers undefined whatever the key.
      def bracket_access(at)
        return insufficient("bracket_access") if @stack.size < 2

        key = @stack.pop
        target = @stack.pop
        case target
        when Array then list_index(at, target, key)
        when Hash, Duration, Predicator::Date, Predicator::DateTime then map_key(at, target, key)
        else push(at, UNDEFINED)
        end
      end

      def list_index(at, list, key)
        return mismatch("bracket_access", "an integer index", key) unless key.is_a?(Integer)

        push(at, key.negative? || key >= list.size ? UNDEFINED : list[key])
      end

      def map_key(at, target, key)
        unless key.is_a?(String) || key.is_a?(Integer) || ATOM_KEYS.any? { |atom| atom.equal?(key) }
          return mismatch("bracket_access", "a string key", key)
        end

        push(at, member(target, key))
      end

      def member(target, key)
        case target
        when Hash then target.fetch(key, UNDEFINED)
        when Duration then DURATION_UNITS.include?(key) ? target.public_send(key) : UNDEFINED
        else UNDEFINED
        end
      end

      def membership_in(at) = membership(at, "in")
      def membership_contains(at) = membership(at, "contains")

      # `left in right` and `left contains right`: undefined on either side
      # answers undefined; otherwise the list side (right for in, left for
      # contains) must be a list. A member matches by the equality `EQ` uses,
      # with one difference: it answers false where `EQ` answers undefined,
      # so null is found in a list holding null and undefined never is.
      def membership(at, operation)
        return insufficient(operation) if @stack.size < 2

        right = @stack.pop
        left = @stack.pop
        return push(at, UNDEFINED) if UNDEFINED.equal?(left) || UNDEFINED.equal?(right)

        list, sought = operation == "in" ? [right, left] : [left, right]
        return mismatch(operation, "a list", list) unless list.is_a?(Array)

        push(at, list.any? { |item| Compare.loose_equal?(sought, item, by_instant: false) })
      end

      # Pops count values and pushes them as one list, deepest first, which
      # is source order.
      def make_list(at, count)
        return insufficient("make_list") if @stack.size < count

        push(at, @stack.pop(count))
      end
    end
    private_constant :Access
  end
end
