# frozen_string_literal: true

module Predicator
  module Emitter
    # Chains, emitted into the walk that includes this module. A chain is a
    # run of nodes each leaning on the one child the source writes beside it
    # rather than inside it: a postfix step's object, a binary operator's
    # left operand. The parser reads a chain in a loop, and so does this
    # walk: it collects the spine, emits the innermost operand, then each
    # link from the inside out, which is the post-order a recursive walk
    # would give. Only the spine is flattened; a right operand or a key goes
    # through the walk a level deeper.
    module Chains
      # The nodes a chain is made of.
      KINDS = [Ast::PropertyAccess, Ast::BracketAccess, Ast::Cast, Ast::Comparison, Ast::Arithmetic,
               Ast::Membership, Ast::LogicalAnd, Ast::LogicalOr].freeze

      private

      def chain(root)
        spine = [root]
        spine << leaning(spine.last) while KINDS.include?(leaning(spine.last).class)
        spine.reverse.each_with_object(visit(leaning(spine.last))) { |node, out| link(node, out) }
      end

      def leaning(node)
        case node
        when Ast::PropertyAccess, Ast::BracketAccess then node.object
        when Ast::Cast then node.expression
        else node.left
        end
      end

      # Appends one link's own instructions to the chain emitted so far.
      def link(node, out)
        case node
        when Ast::LogicalAnd, Ast::LogicalOr then jump_over(node, out)
        when Ast::PropertyAccess, Ast::Cast then out << own(node, step(node))
        else out.concat(visit(node.is_a?(Ast::BracketAccess) ? node.key : node.right)) << own(node, step(node))
        end
      end

      # The instruction a link emits after its operands.
      def step(node)
        case node
        when Ast::PropertyAccess then ["access", node.property]
        when Ast::Cast then ["cast", node.type_name]
        when Ast::BracketAccess then ["bracket_access"]
        else OPCODES.fetch(node.operator).dup
        end
      end

      # `and` and `or`: a jump between the operands, past the right one.
      def jump_over(node, out)
        right = visit(node.right)
        opcode = node.is_a?(Ast::LogicalAnd) ? "jump_if_falsy_or_pop" : "jump_if_true_or_pop"
        out.push(own(node, [opcode, right.size + 1])).concat(right)
      end
    end
    private_constant :Chains
  end
end
