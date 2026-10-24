# frozen_string_literal: true

module Predicator
  module Parser
    # How a refusal's message names a token, in the reference's words: the
    # word connectives uppercase whatever case the source wrote, the end of
    # input in words, a string in double quotes, and every other token that
    # carries a value as its kind and that value in single quotes. Read into
    # the parse that includes this module.
    module TokenText
      # The tokens named without their value.
      FIXED = {
        undefined: "'undefined'", null: "'null'", gt: "'>'", lt: "'<'", gte: "'>='", lte: "'<='", eq: "'='",
        ne: "'!='", equal_equal: "'=='", strict_equal: "'==='", strict_ne: "'!=='", and_op: "'AND'",
        or_op: "'OR'", not_op: "'NOT'", in_op: "'IN'", contains_op: "'CONTAINS'", ago_op: "'ago'",
        from_op: "'from'", now_op: "'now'", next_op: "'next'", last_op: "'last'", lparen: "'('", rparen: "')'",
        lbracket: "'['", rbracket: "']'", lbrace: "'{'", rbrace: "'}'", colon: "':'", double_colon: "'::'",
        comma: "','", semicolon: "';'", dot: "'.'", plus: "'+'", minus: "'-'", multiply: "'*'", divide: "'/'",
        modulo: "'%'", and_and: "'&&'", or_or: "'||'", bang: "'!'", if_kw: "'if'", else_kw: "'else'",
        while_kw: "'while'", eof: "end of input"
      }.freeze

      # The kind a token carrying a value is named by.
      KINDS = {
        integer: "number", float: "number", fractional_number: "number", boolean: "boolean", date: "date",
        datetime: "datetime", identifier: "identifier", function_name: "function",
        qualified_function_name: "function", duration_unit: "duration unit"
      }.freeze

      private

      def describe(token)
        return FIXED.fetch(token.type) if FIXED.key?(token.type)
        return %(string "#{token.value}") if token.type == :string

        "#{KINDS.fetch(token.type)} '#{spelling(token.value)}'"
      end

      # A float as the reference writes one; an infinite one, which the
      # lexer answers for a decimal too long for a finite Float where the
      # reference's lexer raises, as Ruby writes it.
      def spelling(value)
        case value
        when Float then value.finite? ? FloatText.spell(value) : value.to_s
        when Lexer::Fraction then "#{value.whole}.#{value.fraction}"
        else value.to_s
        end
      end
    end
    private_constant :TokenText
  end
end
