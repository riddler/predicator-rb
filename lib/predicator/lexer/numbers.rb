# frozen_string_literal: true

module Predicator
  module Lexer
    # Numbers and the duration units written after them, read into the scan
    # that includes this module.
    #
    # A number is decimal digits with at most one decimal point, which a
    # digit must follow: `1.` is the number 1 and then a dot. There is no
    # sign and no exponent. A number followed by a duration unit is an
    # integer token, or a fractional number token where it has a point, then
    # one token per unit; a number followed by anything else is an integer
    # or a float token, so `1.5x` is a float and then an identifier.
    #
    # The units are read one after another, the two-letter spellings (`ms`,
    # `mo`) before the one-letter ones, and the read stops at the first
    # character that is not a unit: `5days` is 5, the unit `d`, and the
    # identifier `ays`.
    #
    # After the FIRST unit the reference's lexer goes on from a copy of the
    # text that starts just after that unit and ends at the first line feed
    # past the copy's first character. Any further units are read inside
    # that copy, and the source from that line feed on is not read. The
    # column advances by the grapheme clusters, not the characters, between
    # the end of the number and the start of what the copy holds after the
    # units, the dropped text included. Both are reproduced here, the corpus
    # fixing neither: `5d x`, a line feed and `y` scans as 5, `d` and `x` at
    # column 6, then the end of input; `5dh`, a line feed and `x` scans as
    # 5, `d`, `h` and the end of input at column 6 of line 1.
    module Numbers
      # The units a duration names, the two-letter spellings first.
      UNIT = /m[so]|[ydhmsw]/

      private

      # A decimal too long for a finite Float reads as an infinite one: the
      # reference's lexer raises there, and refusing the literal is left to
      # the stage that emits it.
      def number
        text = @scanner.scan(/[0-9]+(?:\.[0-9]+)?/)
        whole, fraction = text.split(".")
        unless @scanner.match?(UNIT)
          return emit(fraction ? :float : :integer, fraction ? Float(text) : Integer(whole, 10), text.length)
        end

        leading = fraction ? Fraction.new(whole: Integer(whole, 10), fraction:) : Integer(whole, 10)
        emit(fraction ? :fractional_number : :integer, leading, text.length)
        units
      end

      def units
        text = +""
        dropped = nil
        while (unit = @scanner.scan(UNIT))
          @tokens << Token.new(type: :duration_unit, line: @line, column: @column + text.length,
                               length: unit.length, value: unit)
          text << unit
          dropped ||= keep_line
        end
        @column += consumed(text, dropped)
        nil
      end

      # After the first unit: goes on scanning over the text from here to the
      # first line feed past its first character alone, and answers the text
      # dropped after it ("" when the kept text runs to the end of the source).
      def keep_line
        line = @scanner.check(/.[^\n]*/m) || ""
        return "" if @scanner.pos + line.bytesize == @scanner.string.bytesize

        dropped = @scanner.string.byteslice((@scanner.pos + line.bytesize)..)
        @scanner = StringScanner.new(line)
        @chain_end = 0
        dropped
      end

      # The grapheme clusters the units and the dropped text spanned, as the
      # reference counts them. The units are ASCII letters, so only the
      # cluster just after them can join the last; a carriage return ending
      # the kept text joins the dropped line feed.
      def consumed(unit_text, dropped)
        count = "#{unit_text}#{@scanner.check(/\X/)}".scan(/\X/).size - (@scanner.eos? ? 0 : 1)
        return count if dropped.empty?

        count + dropped.scan(/\X/).size - (!@scanner.eos? && @scanner.string.end_with?("\r") ? 1 : 0)
      end
    end
    private_constant :Numbers
  end
end
