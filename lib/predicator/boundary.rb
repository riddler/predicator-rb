# frozen_string_literal: true

require_relative "values"
require_relative "errors"

module Predicator
  # The value boundary: where a value a host hands in (a context, a literal
  # operand of an instruction list it built, the answer of one of its
  # functions) is checked against the value domain before an evaluation
  # holds it, and where an argument handed to a host function is copied.
  #
  # The domain is nil, true and false, an Integer, a finite Float, a String
  # in UTF-8 (or US-ASCII) that is valid in its encoding, an Array of
  # values, a Hash of keys to values, {Predicator::UNDEFINED}, a
  # {Predicator::Date}, a {Predicator::DateTime} and a {Predicator::Duration}.
  # A map key is a String, an Integer, true, false, nil or
  # {Predicator::UNDEFINED}, the keys a bracket access reads; a key of the
  # context itself, the name a load reads, is a String.
  # A value outside it is refused with an {EvaluationError}, never raised,
  # under one of these reasons:
  #
  # - "unsupported_host_value": a value the domain has no member for (a
  #   Symbol, a Time, any other object), a map key outside the keys above,
  #   or a String that is not valid UTF-8 text;
  # - "non_finite_number": a Float that is not finite;
  # - "cyclic_value": a list or a map that contains itself;
  # - "depth_limit_exceeded": lists and maps nested past {DEPTH_LIMIT}
  #   levels, the outermost counting as the first.
  #
  # The walks are iterative, so a value deeper than the stack is refused
  # rather than exhausting it, and each list or map is walked once however
  # many paths reach it. The module holds no state. It is private to the
  # package.
  module Boundary
    # How deep lists and maps may nest in a value that crosses the boundary:
    # 100 levels, the bound the tagged codec holds a text to.
    DEPTH_LIMIT = 100

    # The String encodings a String in the domain may carry.
    TEXT_ENCODINGS = [Encoding::UTF_8, Encoding::US_ASCII].freeze

    # The keys a map may have besides a String and an Integer.
    MAP_KEY_ATOMS = [true, false, nil, UNDEFINED].freeze

    module_function

    # The refusal of what an evaluation is handed, or nil when all of it is
    # in the domain: the context's keys, then its values, then every `lit`
    # operand of the instruction list, in order.
    #
    # @param instructions [Array] the instruction list
    # @param context [Hash] the context
    # @return [EvaluationError, nil]
    def input_refusal(instructions, context)
      root_refusal(context) || refusal(context, "the context") ||
        instructions.each_with_index.lazy.filter_map do |instruction, at|
          next unless instruction.is_a?(Array) && instruction.first == "lit" && instruction.size == 2

          refusal(instruction.last, "the literal at index #{at}")
        end.first
    end

    # The refusal of a context key that is not a String, or nil.
    def root_refusal(context)
      key = context.each_key.find { |name| !name.is_a?(String) }
      return unless key || context.key?(key)

      EvaluationError.new(reason: "unsupported_host_value",
                          message: "the context has the key #{key.inspect}, which is not a String")
    end

    # The refusal of a value, or nil when it is in the domain.
    #
    # @param value [Object]
    # @param subject [String] what the value is, for the message
    # @return [EvaluationError, nil]
    def refusal(value, subject)
      reason, detail = fault(value)
      EvaluationError.new(reason:, message: "#{subject} #{detail}") if reason
    end

    # The first fault of a value, as a reason and a phrase, or nil.
    def fault(value) = Check.new.fault(value)

    # The fault of a value that is not a list or a map, or nil.
    def leaf_fault(value)
      case value
      when nil, true, false, Integer, Predicator::Date, Predicator::DateTime, Duration, Array, Hash then nil
      when Float then ["non_finite_number", "holds the float #{value}, which is not finite"] unless value.finite?
      when String then text_fault(value)
      else ["unsupported_host_value", "holds #{value.inspect}, which is not a predicator value"] \
        unless UNDEFINED.equal?(value)
      end
    end

    def text_fault(text)
      return if TEXT_ENCODINGS.include?(text.encoding) && text.valid_encoding?

      ["unsupported_host_value", "holds a String that is not valid UTF-8 text"]
    end

    # The fault of a map's first key outside the keys a map may have, or
    # nil.
    def key_fault(map)
      map.each_key do |key|
        next if key.is_a?(Integer) || MAP_KEY_ATOMS.any? { |atom| atom.equal?(key) }
        return ["unsupported_host_value", "has the key #{key.inspect}, which is not a map key"] unless key.is_a?(String)

        found = text_fault(key)
        return found if found
      end
      nil
    end

    def container?(value) = value.is_a?(Array) || value.is_a?(Hash)
    def members(container) = container.is_a?(Hash) ? container.values : container

    # A copy of a value in the domain that shares no list, map or String
    # with it, so that whatever is done to the copy leaves the value as it
    # was. Every other member of the domain is immutable and is shared. A
    # list or a map reached by two paths is copied once, and the walk is
    # iterative.
    #
    # @param value [Object] a value in the domain, with no cycle
    # @return [Object] the copy
    def copy(value) = container?(value) ? Copy.new.copy(value) : copy_text(value)

    def copy_text(value) = value.is_a?(String) ? value.dup : value

    # One check of one value: a depth-first walk over an explicit stack. A
    # list or a map is :open, on the path, from when its members are queued
    # until the marker queued beneath them is reached, and :done from then
    # on; meeting an open one again is a cycle, and a done one is not walked
    # twice.
    class Check
      def initialize
        @state = {}.compare_by_identity
        @work = []
      end

      def fault(root)
        @work.push([root, 1])
        until @work.empty?
          value, depth = @work.pop
          next leave(value) if depth == :leave

          found = Boundary.leaf_fault(value) || container_fault(value, depth)
          return found if found
        end
        nil
      end

      private

      def leave(container) = @state[container] = :done

      # The fault of a list or a map, or nil having queued its members; nil
      # for any other value and for one already walked.
      def container_fault(value, depth)
        return unless Boundary.container?(value) && @state[value] != :done
        return ["cyclic_value", "holds a list or a map that contains itself"] if @state[value] == :open
        return ["depth_limit_exceeded", "nests past #{DEPTH_LIMIT} levels"] if depth > DEPTH_LIMIT

        (value.is_a?(Hash) && Boundary.key_fault(value)) || enter(value, depth)
      end

      def enter(container, depth)
        @state[container] = :open
        @work.push([container, :leave])
        Boundary.members(container).each { |member| @work.push([member, depth + 1]) }
        nil
      end
    end
    private_constant :Check

    # One copy of one list or map: a depth-first walk over an explicit
    # stack that builds each container after its members.
    class Copy
      def initialize
        @copies = {}.compare_by_identity
        @work = []
      end

      def copy(root)
        @work.push([root, false])
        until @work.empty?
          held, members_built = @work.pop
          next @copies[held] = build(held) if members_built

          enter(held) unless @copies.key?(held)
        end
        @copies[root]
      end

      private

      def enter(container)
        @copies[container] = nil
        @work.push([container, true])
        Boundary.members(container).each { |member| @work.push([member, false]) if Boundary.container?(member) }
      end

      # The copy of one list or map, its members' copies already built.
      def build(container)
        return container.map { |member| take(member) } if container.is_a?(Array)

        container.to_h { |key, member| [key.dup, take(member)] }
      end

      def take(member) = @copies.key?(member) ? @copies[member] : Boundary.copy_text(member)
    end
    private_constant :Copy
  end
  private_constant :Boundary
end
