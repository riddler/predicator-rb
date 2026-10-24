# frozen_string_literal: true

require "strscan"
require_relative "values"
require_relative "errors"
require_relative "iso_text"
require_relative "float_text"
require_relative "lexer/literals"
require_relative "lexer/numbers"

module Predicator
  # The compiler's scanner: source text in, a token stream out, or the one
  # refusal that stopped it. It reads the source with a StringScanner and
  # answers the tokens the reference's lexer answers, at the positions it
  # gives them; there is no partial stream and no recovery.
  #
  # A position counts lines and columns from 1, and a column counts
  # characters (Unicode codepoints, as the reference counts them), never
  # bytes. A space and a tab advance the column by one, a line feed starts
  # the next line, and a carriage return outside a literal advances nothing.
  # One count is the reference's own and not a column: the stretch a run of
  # duration units consumes is counted in grapheme clusters ({Numbers}).
  #
  # The source is a String in UTF-8 whose encoding is valid. The module holds
  # no state; each call scans with its own {Scan}. It is private to the
  # package.
  module Lexer
    # One token. The type is one of the reference's token names, as a
    # Symbol; the length counts the characters of source the token covers.
    # A string token also carries its quote (`:double` or `:single`) and
    # the exclusive end of the literal, which is on a later line than its
    # start when the literal holds a raw line feed. Every other token
    # carries neither.
    #
    # @!attribute [r] value
    #   @return [Object] what the token stands for: an identifier's or a
    #     word's text, an Integer, a Float, a {Fraction}, a String's
    #     content, true or false, {Predicator::UNDEFINED}, nil, a
    #     {Predicator::Date}, a {Predicator::DateTime}, a unit's or an
    #     operator's text; nil for the end of input
    Token = Data.define(:type, :line, :column, :length, :value, :quote, :end_position) do
      def initialize(type:, line:, column:, length:, value: nil, quote: nil, end_position: nil) = super
    end

    # The whole number and the fraction digits of a decimal number written
    # before a duration unit (`0.5h`). The fraction stays the digits written,
    # so a duration is expanded from exact digits rather than from a Float.
    Fraction = Data.define(:whole, :fraction)

    # The extent of a refusal: from its start, inclusive, to its end,
    # exclusive, each a {Predicator::Position}.
    Span = Data.define(:start, :end)

    # Why the source does not scan: a {Predicator::ParseError} (whose
    # position is the span's start) and its {Span}.
    Refusal = Data.define(:error, :span)

    # The words that are not identifiers, by their exact spelling, and the
    # token type and value each one becomes.
    RESERVED = {
      "true" => [:boolean, true], "false" => [:boolean, false],
      "undefined" => [:undefined, UNDEFINED], "null" => [:null, nil],
      "AND" => [:and_op, "AND"], "OR" => [:or_op, "OR"], "NOT" => [:not_op, "NOT"],
      "and" => [:and_op, "and"], "or" => [:or_op, "or"], "not" => [:not_op, "not"],
      "IN" => [:in_op, "IN"], "in" => [:in_op, "in"],
      "CONTAINS" => [:contains_op, "CONTAINS"], "contains" => [:contains_op, "contains"],
      "if" => [:if_kw, "if"], "else" => [:else_kw, "else"], "while" => [:while_kw, "while"],
      "ago" => [:ago_op, "ago"], "from" => [:from_op, "from"], "now" => [:now_op, "now"],
      "next" => [:next_op, "next"], "last" => [:last_op, "last"]
    }.freeze

    # The punctuation, by spelling. A single `&` or `|` is not a token.
    OPERATORS = {
      "===" => :strict_equal, "!==" => :strict_ne, ">=" => :gte, "<=" => :lte, "==" => :equal_equal,
      "!=" => :ne, "&&" => :and_and, "||" => :or_or, "::" => :double_colon, ">" => :gt, "<" => :lt,
      "=" => :eq, "!" => :bang, "+" => :plus, "-" => :minus, "*" => :multiply, "/" => :divide,
      "%" => :modulo, "(" => :lparen, ")" => :rparen, "[" => :lbracket, "]" => :rbracket,
      "{" => :lbrace, "}" => :rbrace, ":" => :colon, "," => :comma, ";" => :semicolon, "." => :dot
    }.freeze

    # Every operator, the longest spelling tried first.
    OPERATOR = Regexp.union(OPERATORS.keys.sort_by { |text| -text.length })

    # Scans source text.
    #
    # @param source [String] UTF-8 text
    # @return [Array<Token>, Refusal] every token, the last of type `:eof`,
    #   or the refusal that stopped the scan
    def self.tokenize(source) = Scan.new(source).run

    # One scan of one source: the scanner, the running line and column, and
    # the tokens so far. Each call to {Lexer.tokenize} makes its own.
    class Scan
      include Literals
      include Numbers

      # What a character starts, tried in order; anything else is
      # punctuation or a refusal.
      STARTS = [[/[ \t\r\n]/, :blank], [/[0-9]/, :number], [/[A-Za-z_]/, :word], [/["']/, :string],
                [/#/, :date]].freeze

      def initialize(source)
        @scanner = StringScanner.new(source)
        @line = 1
        @column = 1
        @tokens = []
        @chain_end = 0
      end

      # @return [Array<Token>, Refusal]
      def run
        until @scanner.eos?
          start = STARTS.find { |pattern, _| @scanner.match?(pattern) }
          refusal = start ? send(start.last) : operator
          return refusal if refusal
        end
        @tokens << Token.new(type: :eof, line: @line, column: @column, length: 0)
      end

      private

      def blank
        @scanner.scan(/[ \t\r\n]+/).each_char do |char|
          if char == "\n"
            @line += 1
            @column = 1
          elsif char != "\r"
            @column += 1
          end
        end
        nil
      end

      # An identifier, a reserved word, or a function's name. A dotted name
      # is one token only where a call follows it; anywhere else its first
      # part stands alone and the dot is the next token. Every later part of
      # a dotted name no call followed ends where the first did, so no call
      # follows it either, and the name is not read again from each part.
      def word
        start = @scanner.pos
        name = @scanner.scan(/[A-Za-z_][A-Za-z0-9_]*/)
        return dotted(name) if start >= @chain_end && @scanner.match?(/\.[A-Za-z_]/)

        type, value = RESERVED.fetch(name) { [:identifier, name] }
        type = :function_name if type == :identifier && call_follows?(@scanner.pos)
        emit(type, value, name.length)
      end

      def dotted(name)
        chain = @scanner.check(/(?:\.[A-Za-z_][A-Za-z0-9_]*)+/)
        after = @scanner.pos + chain.bytesize
        if call_follows?(after)
          @scanner.pos = after
          return emit(:qualified_function_name, name + chain, name.length + chain.length)
        end

        @chain_end = after
        emit(*RESERVED.fetch(name) { [:identifier, name] }, name.length)
      end

      # Whether an opening parenthesis follows the byte offset, past any
      # whitespace. A lookahead only: the scanner is left where it was.
      def call_follows?(offset)
        at = @scanner.pos
        @scanner.pos = offset
        @scanner.match?(/[ \t\r\n]*\(/)
      ensure
        @scanner.pos = at
      end

      def operator
        text = @scanner.scan(OPERATOR)
        return emit(OPERATORS.fetch(text), text, text.length) if text

        refuse("unexpected_character", "Unexpected character '#{@scanner.check(/./m)}'", @line, @column + 1)
      end

      def emit(type, value, length, **literal)
        @tokens << Token.new(type:, line: @line, column: @column, length:, value:, **literal)
        @column += length
        nil
      end

      # A refusal at the running position, spanning to the end given.
      def refuse(reason, message, end_line, end_column)
        position = Position.new(line: @line, column: @column)
        Refusal.new(error: ParseError.new(reason:, message:, position:),
                    span: Span.new(start: position, end: Position.new(line: end_line, column: end_column)))
      end
    end
    private_constant :Scan
  end
  private_constant :Lexer
end
