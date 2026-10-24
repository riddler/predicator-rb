# frozen_string_literal: true

module Predicator
  module Evaluator
    # What every part of {JsonScan} shares: the byte at its offset, `@at`,
    # over its bytes, `@bytes`, and the faults it throws as `:fault` with the
    # sentence the text is refused with. The reference's reader reports
    # three kinds: an unexpected byte at its offset, the end of the input,
    # and a sequence it cannot read (its own report of that last kind is a
    # term of its host language, so a sequence here is reported in a
    # sentence of the same form as the other two).
    module JsonFaults
      private

      # The byte at the scan, or nil at the end.
      def here = @bytes.getbyte(@at)

      # The byte at the scan; the end of the text is a fault here.
      def present = here || ending(@at)

      def expect(byte)
        unexpected unless present == byte
        @at += 1
      end

      def unexpected
        throw :fault, format("Invalid JSON: unexpected byte 0x%<byte>02X at position %<at>d", byte: present, at: @at)
      end

      def ending(at) = throw(:fault, "Invalid JSON: unexpected end of input at position #{at}")
      def sequence(at) = throw(:fault, "Invalid JSON: unexpected sequence at position #{at}")
    end
    private_constant :JsonFaults

    # A JSON string's bytes, as the reference's reader reads them: a control
    # byte must be escaped; the bytes from 0x80 must be well-formed UTF-8,
    # refused at the first byte where the sequence breaks; and a `\u` escape
    # must have its four hexadecimal digits, a high surrogate must be
    # followed by a `\u` escape of a low surrogate, and a low surrogate must
    # not stand alone.
    #
    # Where the reference reads an escape's bytes ahead, it reports a text
    # too short to hold them (six bytes from the backslash, twelve for a
    # surrogate pair) as the end of the whole input, not of the string.
    module JsonStrings
      include JsonFaults

      # The bytes a backslash in a string may precede, but for `u`.
      ESCAPES = '"\\/bfnrt'.bytes.freeze
      # For each UTF-8 lead byte, the range each byte after it must fall in.
      CONTINUATIONS = [
        [0xC2..0xDF, [0x80..0xBF]], [0xE0..0xE0, [0xA0..0xBF, 0x80..0xBF]],
        [0xE1..0xEC, [0x80..0xBF] * 2], [0xED..0xED, [0x80..0x9F, 0x80..0xBF]], [0xEE..0xEF, [0x80..0xBF] * 2],
        [0xF0..0xF0, [0x90..0xBF] + ([0x80..0xBF] * 2)], [0xF1..0xF3, [0x80..0xBF] * 3],
        [0xF4..0xF4, [0x80..0x8F] + ([0x80..0xBF] * 2)]
      ].freeze
      # The high and the low surrogates.
      HIGH = 0xD800..0xDBFF
      LOW = 0xDC00..0xDFFF

      private

      # A string, from its opening quote past its closing one.
      def string
        @at += 1
        content(present) until here == 0x22
        @at += 1
        :after
      end

      # One byte of a string's content, and what it opens.
      def content(byte)
        case byte
        when 0x5C then escape
        when 0x00..0x1F then unexpected
        when 0x80..0xFF then utf8(byte)
        else @at += 1
        end
      end

      def utf8(lead)
        ranges = CONTINUATIONS.find { |leads, _| leads.cover?(lead) }&.last || unexpected
        @at += 1
        ranges.each do |range|
          unexpected unless range.cover?(present)
          @at += 1
        end
      end

      # An escape, from its backslash.
      def escape
        start = @at
        @at += 1
        return unicode(start) if present == 0x75

        unexpected unless ESCAPES.include?(present)
        @at += 1
      end

      def unicode(start)
        code = code_at(start)
        @at = start + 6
        return unless HIGH.cover?(code) || LOW.cover?(code)

        sequence(start) if LOW.cover?(code)
        low_half(start)
      end

      # The low surrogate a high one at start must be followed by.
      def low_half(start)
        ending(@bytes.bytesize) if @bytes.bytesize - start < 12
        unexpected unless @bytes.byteslice(start + 6, 2) == "\\u"
        sequence(start) unless LOW.cover?(digits(start + 6))
        @at = start + 12
      end

      # The code a `\u` escape at start names.
      def code_at(start)
        ending(@bytes.bytesize) if @bytes.bytesize - start < 6
        digits(start) || sequence(start)
      end

      def digits(start)
        hex = @bytes.byteslice(start + 2, 4)
        hex.to_i(16) if hex.match?(/\A\h{4}\z/)
      end
    end
    private_constant :JsonStrings

    # The scalars of a JSON text besides its strings: numbers and the three
    # literals. A number too large for a Float is a sequence the reference
    # cannot read, reported at the number's first byte.
    module JsonScalars
      include JsonStrings

      # The literal each first byte begins.
      LITERALS = { 0x74 => "true", 0x66 => "false", 0x6E => "null" }.transform_values(&:bytes).freeze

      private

      def number
        start = @at
        @at += 1 if here == 0x2D
        present == 0x30 ? @at += 1 : digits_run
        fraction_and_exponent
        token = @bytes.byteslice(start, @at - start)
        sequence(start) if token.match?(/[.eE]/) && !JSON.parse(token).finite?
        :after
      end

      def fraction_and_exponent
        if here == 0x2E
          @at += 1
          digits_run
        end
        return unless [0x65, 0x45].include?(here)

        @at += 1
        @at += 1 if [0x2B, 0x2D].include?(here)
        digits_run
      end

      def digits_run
        unexpected unless present.between?(0x30, 0x39)
        @at += 1 while here&.between?(0x30, 0x39)
      end

      def literal(bytes)
        bytes.each { |byte| expect(byte) }
        :after
      end
    end
    private_constant :JsonScalars

    # Finds the first fault in a JSON text, by byte offset, as the
    # reference's JSON reader reports it. JSON.parse is asked to read only a
    # text this has accepted, because the sentence a malformed text is
    # refused with names the offending byte and its offset, and Ruby's
    # parser's own messages are its own.
    #
    # Content after the value is refused at the first byte after the value,
    # a space included, as the reference refuses it. The scan walks the
    # text's bytes once, keeping the open lists and maps on a stack of its
    # own rather than recursing, so a deeply nested text cannot exhaust
    # Ruby's stack. It holds no state between scans.
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
      # @param text [String] the text, its bytes read as UTF-8
      # @param limit [Integer] the deepest level of lists and maps accepted
      # @return [String, nil]
      def self.fault(text, limit) = new(text, limit).fault

      def initialize(text, limit)
        @bytes = text.b
        @limit = limit
        @at = 0
        @open = []
      end

      def fault
        catch(:fault) do
          space
          walk
          trailing
        end
      end

      private

      # Only space may follow the value; anything else is refused at the
      # first byte after the value.
      def trailing
        after = @at
        space
        return if @at == @bytes.bytesize

        @at = after
        unexpected
      end

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
    end
    private_constant :JsonScan
  end
end
