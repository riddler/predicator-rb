# frozen_string_literal: true

require_relative "values"
require_relative "errors"
require_relative "lexer"
require_relative "ast"
require_relative "parser"
require_relative "emitter/chains"
require_relative "emitter/statements"

module Predicator
  # The compiler's last stage: the syntax tree the {Parser} builds in, the
  # instruction list the evaluator runs out, or the one refusal that stopped
  # it. It is a post-order walk, the reference's: an operand's instructions
  # come before the instruction that consumes it, and the short-circuiting
  # pair puts its jump between its two operands, since what the jump skips
  # is the right one.
  #
  # The operands are predicator values, the ones the evaluator takes: a date
  # literal is a {Predicator::Date}, a decimal a Float, `undefined`
  # {Predicator::UNDEFINED}. Written in the conformance corpus's tagged
  # encoding they are the corpus's instructions.
  #
  # The shapes the walk emits:
  #
  # - a literal is `lit`; a list whose every element is a literal or a
  #   string is one `lit` carrying the list, and any other list is its
  #   elements then `make_list`;
  # - an object is `object_new`, then each entry's value and an
  #   `object_set` of its key, in the order written;
  # - `a and b` is `a`, a `jump_if_falsy_or_pop` past `b`, then `b`; `or`
  #   the same with `jump_if_true_or_pop`;
  # - in a program, an assignment is its location's segments (the root's
  #   name, each property's name, each bracket's key), its value and a
  #   `store` of the segment count; any other expression statement is the
  #   expression and a `pop`; an `if` is its condition, a
  #   `pop_jump_if_falsy` past the then block (and past the `jump` that ends
  #   it when there is an else block), the block, and that `jump` past the
  #   else block; a `while` is its condition, a `pop_jump_if_falsy` past the
  #   body and its back edge, the body, then a `jump_backward` to the
  #   condition's first instruction.
  #
  # Each instruction is annotated with the position and the span of the node
  # that emitted it ({Entry}); an `object_set` carries its key's, a `store`
  # its location root's position and its statement's span, and a `pop` the
  # expression's own. Every store also carries the node behind each segment
  # of the location it writes: the root, each property access, each bracket
  # key.
  #
  # One refusal is not the reference's, whose compiler raises there: a
  # decimal literal too large for a finite Float is refused with the reason
  # `number_out_of_range`, over the literal, as a value.
  #
  # A chain the parser read in a loop (nodes leaning on their left operand
  # or their object, as a run of binary operators or of postfix steps
  # builds) is walked in a loop here too, so a long chain takes no deeper a
  # stack than a short one; anything nested inside a node is walked a level
  # deeper, which the parser's depth limit bounds. Where the stack the walk
  # runs on runs out all the same, the source is refused under the parser's
  # reason, `nesting_depth_exceeded`, rather than raising.
  #
  # The module holds no state; each call walks with its own {Walk}. It is
  # private to the package.
  module Emitter
    # One instruction and the node behind it: that node's position and span,
    # and on a `store` the node behind each segment, root first (nil on any
    # other instruction).
    Entry = Data.define(:instruction, :position, :span, :segments)

    # The message a decimal literal too large for a finite Float is refused
    # with. The reference has none: its compiler raises there.
    OUT_OF_RANGE = "Number literal is outside the range this implementation can represent"

    # The opcode each operator node emits, frozen: each instruction emitted
    # is a copy, so no caller holds the table's own arrays.
    OPCODES = {
      gt: %w[compare GT], lt: %w[compare LT], gte: %w[compare GTE], lte: %w[compare LTE],
      equal_equal: %w[compare EQ], ne: %w[compare NE], strict_eq: %w[compare STRICT_EQ],
      strict_ne: %w[compare STRICT_NE], add: ["add"], subtract: ["subtract"], multiply: ["multiply"],
      divide: ["divide"], modulo: ["modulo"], in: ["in"], contains: ["contains"], minus: ["unary_minus"],
      bang: ["unary_bang"]
    }.transform_values(&:freeze).freeze

    # The tag a refusal is thrown with, to the catch around a walk.
    REFUSED = :refused

    # Emits one expression.
    #
    # @param node [Object] an {Ast} node
    # @return [Array<Entry>, Lexer::Refusal] the annotated instructions, or
    #   the refusal
    def self.emit(node) = Walk.new.run(node) { |walk| walk.visit(node) }

    # Emits a program, one statement after another.
    #
    # @param program [Ast::Program]
    # @return [Array<Entry>, Lexer::Refusal] the annotated instructions, or
    #   the refusal
    def self.emit_program(program) = Walk.new.run(program) { |walk| walk.statements(program.statements) }

    # One walk of one tree. A refusal is thrown to the catch around the whole
    # walk and is never seen outside this class.
    class Walk
      include Chains
      include Statements

      # The method that emits each kind of expression node.
      VISITS = {
        Ast::Literal => :literal, Ast::StringLiteral => :literal, Ast::Identifier => :identifier,
        Ast::Unary => :prefixed, Ast::LogicalNot => :prefixed, Ast::ListLiteral => :list,
        Ast::ObjectLiteral => :object, Ast::FunctionCall => :call, Ast::Duration => :duration,
        Ast::RelativeDate => :relative_date
      }.merge(Chains::KINDS.to_h { |kind| [kind, :chain] }).freeze

      # The walk in the block, or the refusal it threw; a stack exhausted
      # before the walk finished is refused over the whole tree.
      def run(root)
        catch(REFUSED) { yield self }
      rescue SystemStackError
        refuse(root, "nesting_depth_exceeded", "Expression nests deeper than the stack this compilation runs " \
                                               "on can follow, short of the depth limit of " \
                                               "#{Parser::DEPTH_LIMIT} levels", thrown: false)
      end

      # The instructions of one expression node.
      def visit(node) = send(VISITS.fetch(node.class), node)

      private

      def literal(node) = [own(node, ["lit", value_of(node)])]

      def identifier(node) = [own(node, ["load", node.name])]

      # A unary operator or `not`: the operand, then the operator.
      def prefixed(node)
        visit(node.operand) << own(node, node.is_a?(Ast::LogicalNot) ? ["not"] : OPCODES.fetch(node.operator).dup)
      end

      # A list whose every element is a literal or a string is one `lit`
      # carrying the list; any other list is its elements and `make_list`.
      def list(node)
        if node.elements.all? { |element| [Ast::Literal, Ast::StringLiteral].include?(element.class) }
          return [own(node, ["lit", node.elements.map { |element| value_of(element) }])]
        end

        each_visited(node.elements) << own(node, ["make_list", node.elements.size])
      end

      # `object_new`, then each entry's value and an `object_set` carrying
      # its key's position, in the order written.
      def object(node)
        node.entries.each_with_object([own(node, ["object_new"])]) do |(key, value), out|
          out.concat(visit(value)) << own(key, ["object_set", key.name])
        end
      end

      def call(node) = each_visited(node.arguments) << own(node, ["call", node.name, node.arguments.size])

      # One instruction carrying the units in the order written.
      def duration(node) = [own(node, ["duration", node.units.map { |amount, unit| [amount, unit] }])]

      def relative_date(node) = visit(node.duration) << own(node, ["relative_date", node.direction.to_s])

      def each_visited(nodes) = nodes.each_with_object([]) { |node, out| out.concat(visit(node)) }

      # A literal's value; a Float the domain has no finite member for is
      # refused over the literal.
      def value_of(node)
        value = node.value
        refuse(node, "number_out_of_range", OUT_OF_RANGE) if value.is_a?(Float) && !value.finite?
        value
      end

      def own(node, instruction) = Entry.new(instruction:, position: node.position, span: node.span, segments: nil)

      # The refusal over a node, thrown to the catch around the walk or,
      # outside it, answered.
      def refuse(node, reason, message, thrown: true)
        refusal = Lexer::Refusal.new(error: ParseError.new(reason:, message:, position: node.position),
                                     span: node.span)
        thrown ? throw(REFUSED, refusal) : refusal
      end
    end
    private_constant :Walk
  end
  private_constant :Emitter
end
