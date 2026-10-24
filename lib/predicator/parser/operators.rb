# frozen_string_literal: true

module Predicator
  module Parser
    # The operator levels of the expression grammar, from `OR` down to the
    # prefix operators, read into the parse that includes this module.
    module Operators
      # Each level's operator tokens and the operator each one is.
      OR = { or_op: :or, or_or: :or }.freeze
      AND = { and_op: :and, and_and: :and }.freeze
      ADDITIVE = { plus: :add, minus: :subtract }.freeze
      MULTIPLICATIVE = { multiply: :multiply, divide: :divide, modulo: :modulo }.freeze
      NEGATIONS = %i[not_op bang].freeze
      UNARY = { minus: :minus, bang: :bang }.freeze

      # The comparison and membership tokens: the node each builds and its
      # operator.
      RELATIONS = {
        gt: [Ast::Comparison, :gt], lt: [Ast::Comparison, :lt], gte: [Ast::Comparison, :gte],
        lte: [Ast::Comparison, :lte], equal_equal: [Ast::Comparison, :equal_equal], ne: [Ast::Comparison, :ne],
        strict_equal: [Ast::Comparison, :strict_eq], strict_ne: [Ast::Comparison, :strict_ne],
        in_op: [Ast::Membership, :in], contains_op: [Ast::Membership, :contains]
      }.freeze

      # A bare `=` where an expression goes on.
      EQUALS = "'=' is not an equality operator - use '==' for equality. " \
               "Assignment is only valid at the start of a statement."

      private

      def logical_or = chain(OR, :logical_and) { |_, left, right, at| Ast::LogicalOr.new(left:, right:, **at) }

      def logical_and = chain(AND, :logical_not) { |_, left, right, at| Ast::LogicalAnd.new(left:, right:, **at) }

      def addition = chain(ADDITIVE, :multiplication) { |*parts| arithmetic(*parts) }

      def multiplication = chain(MULTIPLICATIVE, :unary) { |*parts| arithmetic(*parts) }

      def arithmetic(operator, left, right, at) = Ast::Arithmetic.new(operator:, left:, right:, **at)

      # A left-associative level: operands read by the method named, joined
      # by the operators given, each join built by the block.
      def chain(operators, operand)
        left = send(operand)
        while (operator = operators[peek.type])
          token = advance
          right = send(operand)
          left = yield(operator, left, right, infix(token, left, right))
        end
        left
      end

      # The higher of the bang's two places: here it negates a whole
      # comparison, below the comparison it negates an operand.
      def logical_not
        return comparison unless NEGATIONS.include?(peek.type)

        token = advance
        operand = descend { logical_not }
        Ast::LogicalNot.new(operand:, **prefixed(token, operand))
      end

      def comparison
        left = addition
        refuse("assignment_in_expression", EQUALS, peek) if at?(:eq)
        kind, operator = RELATIONS[peek.type]
        return left unless kind

        token = advance
        right = addition
        kind.new(operator:, left:, right:, **infix(token, left, right))
      end

      # A minus never folds into the number after it: `-5` is a negation.
      def unary
        operator = UNARY[peek.type]
        return postfix unless operator

        token = advance
        operand = descend { unary }
        Ast::Unary.new(operator:, operand:, **prefixed(token, operand))
      end
    end
    private_constant :Operators
  end
end
