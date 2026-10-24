# frozen_string_literal: true

require_relative "values"
require_relative "errors"
require_relative "float_text"
require_relative "duration_text"
require_relative "lexer"
require_relative "ast"
require_relative "parser/token_text"
require_relative "parser/operators"
require_relative "parser/postfix"
require_relative "parser/primaries"
require_relative "parser/durations"
require_relative "parser/statements"

module Predicator
  # The compiler's second stage: the token stream the {Lexer} answers in,
  # the reference's syntax tree ({Ast}) out, or the one refusal that stopped
  # it. It is a recursive descent over the reference's grammar, with its
  # precedence, lowest first:
  #
  #     program        -> statement ( ";" statement )* ";"?
  #     statement      -> if | while | location "=" expression | expression
  #     expression     -> logical_or
  #     logical_or     -> logical_and ( ( "OR" | "||" ) logical_and )*
  #     logical_and    -> logical_not ( ( "AND" | "&&" ) logical_not )*
  #     logical_not    -> ( "NOT" | "!" ) logical_not | comparison
  #     comparison     -> addition ( comparison_op | "in" | "contains" ) addition )?
  #     addition       -> multiplication ( ( "+" | "-" ) multiplication )*
  #     multiplication -> unary ( ( "*" | "/" | "%" ) unary )*
  #     unary          -> ( "-" | "!" ) unary | postfix
  #     postfix        -> primary ( "[" expression "]" | "." name | "::" type )*
  #
  # The binary operators associate to the left; a comparison takes one
  # operator at most, so a second is a token after a finished expression.
  # A statement ending in a closing brace needs no separator before the
  # next; a program holds one statement at least.
  #
  # A refusal is a {Lexer::Refusal}: a {Predicator::ParseError} carrying the
  # reference's message, the position and span of the token it names, and a
  # reason, which is this package's token for the refusal. Nothing raises.
  #
  # One refusal is not the reference's, which follows a source as deep as it
  # nests: a source that nests more than {DEPTH_LIMIT} levels is refused
  # with the reason `nesting_depth_exceeded`, at the token the descent
  # stopped on, rather than left to exhaust the stack. A level is counted
  # each time the descent re-enters the whole expression (inside a
  # parenthesis, a list, an object, an index, a call's arguments, a
  # statement's condition or value), for each prefix operator, a relative
  # date's operand, a block's statements, an `else if` and a statement's
  # assignment probe; a chain of left-associative operators or of postfix
  # steps is read in a loop and costs none. Where the stack a parse runs on
  # is too small to reach the limit, as a Fiber's default stack is, the
  # source is refused under the same reason at the token the stack ran out
  # on, with a message saying so, rather than raising.
  #
  # The module holds no state; each call parses with its own {Descent}. It
  # is private to the package.
  module Parser
    # How many levels a source may nest, the whole expression counting as
    # the first. A source at exactly this depth parses. It is above the 300
    # parentheses the reference's compile transcript compiles, and below
    # the depth the costliest nesting reaches on a thread's default stack.
    DEPTH_LIMIT = 400

    # The seven scalar type names a cast may name, in the reference's order.
    CAST_TYPE_NAMES = %w[integer float string boolean date datetime duration].freeze

    # The tag a refusal is thrown with, to the catch around a parse or a
    # probe.
    REFUSED = :refused

    # Parses one expression.
    #
    # @param tokens [Array<Lexer::Token>] a stream the lexer answered, which
    #   ends in its `:eof` token
    # @return [Object, Lexer::Refusal] the expression's {Ast} node, or the
    #   refusal
    def self.parse(tokens) = Descent.new(tokens).whole_expression

    # Parses a program: one or more statements.
    #
    # @param tokens [Array<Lexer::Token>] a stream the lexer answered, which
    #   ends in its `:eof` token
    # @return [Ast::Program, Lexer::Refusal] the program, or the refusal
    def self.parse_program(tokens) = Descent.new(tokens).whole_program

    # One parse of one token stream: the tokens, the cursor and how many
    # productions are open. A refusal is thrown to the catch around the
    # whole parse (or around the assignment probe that discards it) and is
    # never seen outside this class.
    class Descent
      include TokenText
      include Operators
      include Postfix
      include Primaries
      include Durations
      include Statements

      def initialize(tokens)
        @tokens = tokens
        @index = 0
        @depth = 0
      end

      # @return [Object, Lexer::Refusal]
      def whole_expression
        guarded do
          node = expression
          trailing = peek
          refuse("trailing_token", "Unexpected token #{describe(trailing)} after expression", trailing) unless at?(:eof)
          node
        end
      end

      # @return [Ast::Program, Lexer::Refusal]
      def whole_program
        guarded do
          start = start_of(peek)
          statements = statement_sequence(:eof)
          after_statement(peek) unless at?(:eof)
          Ast::Program.new(statements:, position: start,
                           span: between(statements.first.span.start, statements.last.span.end))
        end
      end

      private

      # The parse in the block, or the refusal it threw; a stack exhausted
      # short of the depth limit is refused where it ran out.
      def guarded(&)
        catch(REFUSED, &)
      rescue SystemStackError
        catch(REFUSED) do
          refuse("nesting_depth_exceeded", "Expression nests deeper than the stack this parse runs on can follow, " \
                                           "short of the depth limit of #{DEPTH_LIMIT} levels", peek)
        end
      end

      def peek = @tokens[@index]

      def previous = @tokens[@index - 1]

      def at?(type) = peek.type == type

      def advance
        token = peek
        @index += 1
        token
      end

      # The token, consumed, when it is of the type given; the refusal
      # naming it otherwise.
      def expect(type, reason, message)
        refuse(reason, "#{message} #{describe(peek)}", peek) unless at?(type)
        advance
      end

      # Reads one production one level deeper, or refuses at the token the
      # descent stopped on when the source is already at the limit.
      def descend
        enter
        yield
      ensure
        @depth -= 1
      end

      # The whole expression, one level deeper. It is the production read most
      # often, so it counts its own level rather than through a block.
      def expression
        enter
        logical_or
      ensure
        @depth -= 1
      end

      # Counts one more open production; the ensure of whoever called it counts
      # it back, the refusal included.
      def enter
        @depth += 1
        return if @depth <= DEPTH_LIMIT

        refuse("nesting_depth_exceeded", "Expression nests past the depth limit of #{DEPTH_LIMIT} levels, " \
                                         "the whole expression counting as the first", peek)
      end

      # Throws the refusal: its position is its span's start.
      def refuse(reason, message, token, span = span_of(token))
        error = ParseError.new(reason:, message:, position: span.start)
        throw REFUSED, Lexer::Refusal.new(error:, span:)
      end

      def start_of(token) = Position.new(line: token.line, column: token.column)

      # One past the token's last character; a string token, which may hold
      # a line feed, carries its own.
      def end_of(token) = token.end_position || Position.new(line: token.line, column: token.column + token.length)

      def span_of(token) = Lexer::Span.new(start: start_of(token), end: end_of(token))

      # A node's own token, as its position and its span.
      def leaf(token) = { position: start_of(token), span: span_of(token) }

      # From an opening token to past its closing one.
      def delimited(open, close) = { position: start_of(open), span: between(start_of(open), end_of(close)) }

      # From a node's start to past a token.
      def reaching(node, token) = between(node.span.start, end_of(token))

      # From a prefix token to its operand's end.
      def prefixed(token, operand) = { position: start_of(token), span: between(start_of(token), operand.span.end) }

      # An infix node: at its operator, over its operands.
      def infix(token, left, right) = { position: start_of(token), span: between(left.span.start, right.span.end) }

      def between(start, finish) = Lexer::Span.new(start:, end: finish)
    end
    private_constant :Descent
  end
  private_constant :Parser
end
