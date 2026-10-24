# frozen_string_literal: true

module Predicator
  module Evaluator
    # The bytes of a JSON text's scalars - its strings, numbers and three
    # literals - as {JsonScan} reads them, and the faults it reports. Each
    # method reads from the scan's offset, `@at`, over its bytes, `@bytes`,
    # and moves the offset past what it read, or throws `:fault` with the
    # reason the text is refused with.
    module JsonScalars
      # The bytes a backslash in a string may precede, but for `u`.
      ESCAPES = '"\\/bfnrt'.bytes.freeze
      # The literal each first byte begins.
      LITERALS = { 0x74 => "true", 0x66 => "false", 0x6E => "null" }.transform_values(&:bytes).freeze

      private

      # A string's bytes up to its closing quote. A control byte must be
      # escaped; every other byte, a UTF-8 continuation byte included, is
      # content.
      def string
        @at += 1
        until present == 0x22
          unexpected if here < 0x20
          @at += 1
          escape if @bytes.getbyte(@at - 1) == 0x5C
        end
        @at += 1
        :after
      end

      def escape
        byte = present
        unexpected unless byte == 0x75 || ESCAPES.include?(byte)
        @at += 1
        4.times { hex_digit } if byte == 0x75
      end

      def hex_digit
        unexpected unless present.chr.match?(/\h/)
        @at += 1
      end

      def number
        @at += 1 if here == 0x2D
        present == 0x30 ? @at += 1 : digits
        if here == 0x2E
          @at += 1
          digits
        end
        exponent if [0x65, 0x45].include?(here)
        :after
      end

      def exponent
        @at += 1
        @at += 1 if [0x2B, 0x2D].include?(here)
        digits
      end

      def digits
        unexpected unless present.between?(0x30, 0x39)
        @at += 1 while here&.between?(0x30, 0x39)
      end

      def literal(bytes)
        bytes.each { |byte| expect(byte) }
        :after
      end

      def expect(byte)
        unexpected unless present == byte
        @at += 1
      end

      # The byte at the scan, or nil at the end.
      def here = @bytes.getbyte(@at)

      # The byte at the scan; the end of the text is a fault here.
      def present
        here || throw(:fault, "Invalid JSON: unexpected end of input at position #{@at}")
      end

      def unexpected
        throw :fault, format("Invalid JSON: unexpected byte 0x%<byte>02X at position %<at>d", byte: present, at: @at)
      end
    end
    private_constant :JsonScalars

    # Finds the first fault in a JSON text, by byte offset, the way the
    # reference's JSON reader reports one. JSON.parse is asked to read only a
    # text this has accepted, because the sentence a malformed text is
    # refused with names the offending byte and its offset, and Ruby's
    # parser's own messages are its own.
    #
    # The scan walks the text's bytes once, keeping the open lists and maps
    # on a stack of its own rather than recursing, so a deeply nested text
    # cannot exhaust Ruby's stack. It holds no state between scans.
    class JsonScan
      include JsonScalars

      # The bytes a JSON text may hold between tokens.
      SPACE = [0x20, 0x09, 0x0A, 0x0D].freeze
      # The byte that closes each kind of container.
      CLOSERS = { array: 0x5D, object: 0x7D }.freeze

      # Why text is not a JSON text: "Invalid JSON: " and the fault, or
      # "depth_limit_exceeded" when it nests past limit levels; nil when it
      # is one.
      #
      # @param text [String] UTF-8 text
      # @param limit [Integer] the deepest level of lists and maps accepted
      # @return [String, nil]
      def self.fault(text, limit) = new(text, limit).fault

      def initialize(text, limit)
        @text = text
        @bytes = text.b
        @limit = limit
        @at = 0
        @open = []
      end

      def fault
        catch(:fault) do
          space
          walk
          space
          unexpected if @at < @bytes.bytesize
          encoding_fault
        end
      end

      private

      # Scans one value and, while containers are open, the rest of each.
      def walk
        state = value
        state = state == :first ? first_member : next_member until state == :done
      end

      def first_member
        space
        return close if closer?

        member_start
        value
      end

      def next_member
        return :done if @open.empty?

        space
        return close if closer?

        expect(0x2C)
        space
        member_start
        value
      end

      def closer? = here == CLOSERS.fetch(@open.last)

      def close
        @at += 1
        @open.pop
        :after
      end

      # An object's member opens with its key and a colon.
      def member_start
        return unless @open.last == :object

        unexpected unless present == 0x22
        string
        space
        expect(0x3A)
        space
      end

      # Scans a scalar (answering :after) or enters a container (:first).
      def value
        byte = here
        case byte
        when 0x5B then enter(:array)
        when 0x7B then enter(:object)
        when 0x22 then string
        when 0x2D, 0x30..0x39 then number
        when *LITERALS.keys then literal(LITERALS.fetch(byte))
        else unexpected
        end
      end

      def enter(kind)
        throw :fault, "depth_limit_exceeded" if @open.size >= @limit

        @open.push(kind)
        @at += 1
        :first
      end

      def space
        @at += 1 while SPACE.include?(here)
      end

      # A well-formed text whose bytes are not valid UTF-8 is refused at the
      # first byte that is not.
      def encoding_fault
        return if @text.valid_encoding?

        @at = 0
        @text.each_char do |char|
          break unless char.valid_encoding?

          @at += char.bytesize
        end
        unexpected
      end
    end
    private_constant :JsonScan
  end
end
