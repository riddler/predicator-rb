# frozen_string_literal: true

module Predicator
  module Lexer
    # The string and date literals, read into the scan that includes this
    # module (its scanner, its running line and column, its tokens).
    module Literals
      # The escapes a string literal decodes. Any other escaped character
      # stands for itself, so an unrecognized escape loses its backslash.
      ESCAPES = { "n" => "\n", "t" => "\t", "r" => "\r" }.freeze

      # A literal's run of characters that neither close it nor escape, by
      # its quote.
      PLAIN = { '"' => /[^"\\]*/, "'" => /[^'\\]*/ }.freeze

      # The quote a string token carries, by its character.
      QUOTES = { '"' => :double, "'" => :single }.freeze

      # The refusal of the numeric escape, in either spelling of its letter.
      NUMERIC_ESCAPE = "Unsupported escape sequence \\u in string literal: predicator has no numeric " \
                       "escape; write the character itself (string literals are UTF-8)"

      private

      # A string literal, quoted with `"` or `'`. A raw line feed inside it
      # is content and moves the line; a two-character escape advances the
      # column by two whatever it decodes to, a backslash before a line feed
      # included. A refusal inside the literal spans its opening quote.
      def string
        start = @scanner.pos
        quote = @scanner.getch
        content = read_string(quote)
        return content if content.is_a?(Refusal)

        text = @scanner.string.byteslice(start...@scanner.pos)
        end_line, end_column = after(text.gsub(/\\./m, ".."), @line, @column)
        emit(:string, content, text.length, quote: QUOTES.fetch(quote),
                                            end_position: Position.new(line: end_line, column: end_column))
        move(end_line, end_column)
      end

      # The literal's content, up to and past its closing quote; or the
      # refusal.
      def read_string(quote)
        content = +""
        loop do
          content << @scanner.scan(PLAIN.fetch(quote))
          char = @scanner.getch
          return content if char == quote

          piece = char ? escape(quote) : unterminated(quote)
          return piece if piece.is_a?(Refusal)

          content << piece
        end
      end

      # What the escape after a backslash stands for, or the refusal.
      def escape(quote)
        escaped = @scanner.getch
        return unterminated(quote) if escaped.nil?
        return refuse("unsupported_escape", NUMERIC_ESCAPE, @line, @column + 1) if %w[u U].include?(escaped)

        ESCAPES.fetch(escaped, escaped)
      end

      def unterminated(quote)
        refuse("unterminated_string", "Unterminated #{quote == '"' ? "double" : "single"}-quoted string literal",
               @line, @column + 1)
      end

      # A date or datetime literal, `#...#`. A body holding a `T` is read as
      # a datetime and any other as a date, as {IsoText} reads them (the
      # datetime unbounded in its year, as the reference's literal is). A
      # refusal spans the whole literal: through the closing `#`, or through
      # the end of the source when there is none.
      def date
        @scanner.getch
        body = @scanner.scan(/[^#]*/)
        end_line, end_column = after(body, @line, @column + 1)
        return refuse("unterminated_date", "Unterminated date literal", end_line, end_column) unless @scanner.getch

        type, value = read_date(body)
        return refuse("invalid_#{type}", "Invalid #{type} format: #{body}", end_line, end_column + 1) if value.nil?

        emit(type, value, body.length + 2)
        move(end_line, end_column + 1)
      end

      # Moves the running position past a literal that may span lines.
      def move(line, column)
        @line = line
        @column = column
        nil
      end

      def read_date(body)
        return [:datetime, IsoText.read_instant(body)] if body.include?("T")

        [:date, IsoText.read_date(body)]
      end

      # The line and column just past text that starts at the line and
      # column given: a line feed starts the next line, and every other
      # character, a carriage return included, advances the column by one.
      def after(text, line, column)
        breaks = text.count("\n")
        return [line, column + text.length] if breaks.zero?

        [line + breaks, text.length - text.rindex("\n")]
      end
    end
    private_constant :Literals
  end
end
