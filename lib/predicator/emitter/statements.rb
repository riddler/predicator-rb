# frozen_string_literal: true

module Predicator
  module Emitter
    # A program's statements, emitted into the walk that includes this
    # module. Every statement leaves the stack as it found it: an assignment
    # ends in the `store` that consumes its value, an expression in a `pop`,
    # and an `if` or a `while` consumes its condition in the jump that tests
    # it. The jumps are relative, counted from the jump itself, and carry the
    # statement's own position and span.
    module Statements
      # The instructions of a statement sequence, one statement after
      # another.
      def statements(list) = list.each_with_object([]) { |statement, out| out.concat(statement(statement)) }

      private

      def statement(node)
        case node
        when Ast::Assignment then assignment(node)
        when Ast::If then if_statement(node)
        when Ast::While then while_statement(node)
        else visit(node) << own(node, ["pop"])
        end
      end

      # The condition, a falsy jump past the then block (and past the jump
      # that ends it, when there is an else block), the block, then that
      # jump past the else block.
      def if_statement(node)
        then_block = block(node.then_block)
        else_block = node.else_block && block(node.else_block)
        out = visit(node.condition) << own(node, ["pop_jump_if_falsy", then_block.size + (else_block ? 2 : 1)])
        out.concat(then_block)
        else_block ? jump_past(node, else_block, out) : out
      end

      # The jump that ends a then block, past the else block, then that block.
      def jump_past(node, else_block, out) = out.push(own(node, ["jump", else_block.size + 1])).concat(else_block)

      def block(node) = statements(node.statements)

      # The condition, a falsy jump past the body and its back edge, the
      # body, then the back edge to the condition's first instruction.
      def while_statement(node)
        out = visit(node.condition)
        back = out.size
        body = statements(node.body.statements)
        out.push(own(node, ["pop_jump_if_falsy", body.size + 2])).concat(body)
        out << own(node, ["jump_backward", back + body.size + 1])
      end

      # The location's segments root first, the value, and the store.
      def assignment(node)
        root, links = location(node.target)
        out = [own(root, ["lit", root.name])]
        segments = [root] + links.map { |link| segment(link, out) }
        out.concat(visit(node.value))
        out << Entry.new(instruction: ["store", segments.size], position: root.position, span: node.span, segments:)
      end

      # A location's root identifier and its accesses, root first.
      def location(target)
        links = []
        while target.is_a?(Ast::PropertyAccess) || target.is_a?(Ast::BracketAccess)
          links.unshift(target)
          target = target.object
        end
        [target, links]
      end

      # Appends one access's segment, answering the node behind it: a
      # property's name, or a bracket's key.
      def segment(link, out)
        if link.is_a?(Ast::BracketAccess)
          out.concat(visit(link.key))
          return link.key
        end

        out << own(link, ["lit", link.property])
        link
      end
    end
    private_constant :Statements
  end
end
