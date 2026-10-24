# frozen_string_literal: true

module Predicator
  module Parser
    # The primaries: literals, identifiers, calls, parentheses, lists,
    # objects and relative dates written `next` or `last`, read into the
    # parse that includes this module. Each reader takes the token that
    # started it, already consumed.
    module Primaries
      # The reader for each token a primary may start with; any other token
      # is refused.
      READERS = {
        integer: :number, fractional_number: :fraction, float: :literal, boolean: :literal,
        undefined: :literal, null: :literal, date: :literal, datetime: :literal, string: :string,
        identifier: :identifier, function_name: :call, qualified_function_name: :call,
        lparen: :parenthesized, lbracket: :list, lbrace: :object, next_op: :relative_date,
        last_op: :relative_date, if_kw: :statement_keyword, else_kw: :statement_keyword,
        while_kw: :statement_keyword
      }.freeze

      # What a primary may be, in the refusal of anything else.
      EXPECTED = "Expected number, string, boolean, date, datetime, identifier, function call, list, object, " \
                 "or '(' but found"

      private

      def primary
        reader = READERS.fetch(peek.type, :not_a_primary)
        send(reader, advance)
      end

      def not_a_primary(token) = refuse("expected_primary", "#{EXPECTED} #{describe(token)}", token)

      def statement_keyword(token)
        refuse("statement_keyword", "'#{token.value}' is a statement keyword, not an expression - control flow " \
                                    "is only valid in a program (Predicator.parse_program/2).", token)
      end

      def literal(token) = Ast::Literal.new(value: token.value, **leaf(token))

      # A whole number, or the first component of a duration.
      def number(token) = duration_from(token.value, start_of(token)) || literal(token)

      # A number with a point that a unit follows, which the lexer writes
      # only before a unit; without one, no primary starts with it.
      def fraction(token) = duration_from(token.value, start_of(token)) || not_a_primary(token)

      def string(token) = Ast::StringLiteral.new(value: token.value, quote: token.quote, **leaf(token))

      def identifier(token) = Ast::Identifier.new(name: token.value, **leaf(token))

      # A parenthesis keeps its expression's node and position and widens
      # its span to the parentheses.
      def parenthesized(open)
        inner = expression
        close = expect(:rparen, "expected_close_paren", "Expected ')' but found")
        inner.with(span: between(start_of(open), end_of(close)))
      end

      # A call's name stays whole: the lexer writes a dotted name as one
      # token only where a parenthesis follows it.
      def call(name)
        expect(:lparen, "expected_primary", EXPECTED)
        arguments = items(:rparen) { expression }
        close = expect(:rparen, "expected_close_paren", "Expected ')' but found")
        Ast::FunctionCall.new(name: name.value, arguments:, **delimited(name, close))
      end

      def list(open)
        elements = items(:rbracket) { expression }
        close = expect(:rbracket, "expected_close_bracket", "Expected ']' but found")
        Ast::ListLiteral.new(elements:, **delimited(open, close))
      end

      def object(open)
        entries = items(:rbrace) { entry }
        close = expect(:rbrace, "expected_close_brace", "Expected '}' but found")
        Ast::ObjectLiteral.new(entries:, **delimited(open, close))
      end

      # Comma-separated items up to the closing token, which is left for the
      # caller; none when it comes first.
      def items(closer)
        return [] if at?(closer)

        found = [yield]
        while at?(:comma)
          advance
          found << yield
        end
        found
      end

      # A key, bare or quoted, a colon and a value.
      def entry
        token = peek
        style = token.type == :identifier ? :identifier : token.quote
        unless %i[identifier string].include?(token.type)
          refuse("expected_object_key", "Expected identifier or string for object key but found #{describe(token)}",
                 token)
        end
        advance
        key = Ast::ObjectKey.new(name: token.value, style:, **leaf(token))
        expect(:colon, "expected_object_colon", "Expected ':' after object key but found")
        [key, expression]
      end

      # `next` or `last` and a bare duration; anything else after the word
      # is refused at the token it started at.
      def relative_date(keyword)
        direction = keyword.type == :next_op ? :next : :last
        start = peek
        duration = descend { primary }
        unless duration.is_a?(Ast::Duration)
          refuse("expected_duration", "Expected duration after '#{direction}' but found #{describe(start)}", start)
        end
        Ast::RelativeDate.new(duration:, direction:, **prefixed(keyword, duration))
      end
    end
    private_constant :Primaries
  end
end
