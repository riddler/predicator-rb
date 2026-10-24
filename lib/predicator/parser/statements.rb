# frozen_string_literal: true

module Predicator
  module Parser
    # The statement grammar over the expression grammar, read into the parse
    # that includes this module: sequences, assignments, `if` with its
    # optional `else` and `else if`, `while`, and blocks.
    module Statements
      # The statements a keyword starts.
      KEYWORDS = { if_kw: :if_statement, while_kw: :while_statement, else_kw: :stray_else }.freeze

      # What an assignment may write: an identifier and any run of property
      # and bracket accesses.
      ACCESSES = [Ast::PropertyAccess, Ast::BracketAccess].freeze

      private

      # One statement or more up to the terminator, which is left for the
      # caller. A separator is followed by another statement unless it is
      # the one the terminator may follow; without one, another follows
      # only a statement that ended in a closing brace.
      def statement_sequence(terminator)
        statements = [statement]
        statements << statement while continues?(statements.last, terminator)
        statements
      end

      def continues?(last, terminator)
        return !at?(terminator) && (last.is_a?(Ast::If) || last.is_a?(Ast::While)) unless at?(:semicolon)

        advance
        !at?(terminator)
      end

      def statement
        reader = KEYWORDS[peek.type]
        reader ? send(reader, advance) : assignment_or_expression
      end

      def stray_else(token)
        refuse("unexpected_else", "Unexpected 'else' - an 'else' block must follow an 'if' block.", token)
      end

      # What is left over after a finished statement.
      def after_statement(token)
        stray_else(token) if token.type == :else_kw
        refuse("trailing_token", "Unexpected token #{describe(token)} after statement", token)
      end

      # An assignment when an addition-level expression is followed by `=`,
      # and an expression read again from the start otherwise: a probe that
      # was refused, or no `=` after it, is discarded.
      def assignment_or_expression
        start = @index
        target = catch(REFUSED) { descend { addition } }
        if target.is_a?(Lexer::Refusal) || !at?(:eq)
          @index = start
          return expression
        end

        assignment(target, advance)
      end

      # Past the `=`, a left side that is not a location is refused at it.
      def assignment(target, equals)
        unless location?(target)
          refuse("unassignable_location", "Left side of '=' must be an assignable location - an identifier, " \
                                          "a property access, or a bracket access.", equals)
        end
        value = expression
        Ast::Assignment.new(target:, value:, **infix(equals, target, value))
      end

      def location?(node)
        node = node.object while ACCESSES.any? { |access| node.is_a?(access) }
        node.is_a?(Ast::Identifier)
      end

      def if_statement(keyword)
        condition = expression
        then_block = block
        else_block = else_clause
        Ast::If.new(condition:, then_block:, else_block:, **prefixed(keyword, else_block || then_block))
      end

      # An `else if` is an else block holding the one `if`, at its position
      # and over its span; it nests a level as a block does.
      def else_clause
        return unless at?(:else_kw)

        advance
        return block unless at?(:if_kw)

        nested = descend { if_statement(advance) }
        Ast::Block.new(statements: [nested], position: nested.position, span: nested.span)
      end

      def while_statement(keyword)
        condition = expression
        body = block
        Ast::While.new(condition:, body:, **prefixed(keyword, body))
      end

      # Braces around zero statements or more, one level deeper.
      def block
        open = expect(:lbrace, "expected_open_brace", "Expected '{' to open a block but found")
        statements = at?(:rbrace) ? [] : descend { statement_sequence(:rbrace) }
        close = expect(:rbrace, "expected_close_brace", "Expected '}' to close the block but found")
        Ast::Block.new(statements:, **delimited(open, close))
      end
    end
    private_constant :Statements
  end
end
