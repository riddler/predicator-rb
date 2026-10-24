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
    # After the units the reference's lexer goes on from a copy of the text
    # that ends at the first line feed past the character just after them, so
    # the rest of the source from that line feed on is not read; and it
    # advances its column by the grapheme clusters the units and that
    # dropped text spanned, not by their characters. Both are reproduced
    # here, the corpus fixing neither: `5d x` on one line, then a line
    # feed and `y`, scans as 5, `d` and `x` at column 6 and stops.
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
        column = @column
        names = []
        while (unit = @scanner.scan(UNIT))
          names << unit
          @tokens << Token.new(type: :duration_unit, line: @line, column:, length: unit.length, value: unit)
          column += unit.length
        end
        @column += consumed(names.join)
        nil
      end

      # The grapheme clusters the units and any dropped text spanned, as the
      # reference counts them. The units are ASCII letters, so only the
      # cluster just after them can join the last; a carriage return before
      # the dropped line feed joins it.
      def consumed(unit_text)
        line = @scanner.check(/.[^\n]*/m) || ""
        count = "#{unit_text}#{@scanner.check(/\X/)}".scan(/\X/).size - (line.empty? ? 0 : 1)
        return count if ends_source?(line)

        count + drop_after(line).scan(/\X/).size - (line.end_with?("\r") ? 1 : 0)
      end

      def ends_source?(line) = @scanner.pos + line.bytesize == @scanner.string.bytesize

      # Goes on scanning over the line alone, and answers the text dropped.
      def drop_after(line)
        dropped = @scanner.string.byteslice((@scanner.pos + line.bytesize)..)
        @scanner = StringScanner.new(line)
        @chain_end = 0
        dropped
      end
    end
    private_constant :Numbers
  end
end
