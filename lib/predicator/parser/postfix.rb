# frozen_string_literal: true

module Predicator
  module Parser
    # The postfix steps after a primary, read in a loop into the parse that
    # includes this module: an index, a property and a cast. Each step's
    # node is positioned at what it accesses - the key, the property name,
    # the type name - and spans from its object's start.
    module Postfix
      # Each step's opening token and the method that reads the rest.
      STEPS = { lbracket: :index, dot: :property, double_colon: :cast }.freeze

      # The tokens that may name a property: an identifier, and the five
      # relative-date words, which the lexer reserves.
      PROPERTY_NAMES = %i[identifier last_op next_op ago_op from_op now_op].freeze

      private

      def postfix
        node = primary
        while (step = STEPS[peek.type])
          advance
          node = send(step, node)
        end
        node
      end

      def index(object)
        key_token = peek
        key = expression
        close = expect(:rbracket, "expected_close_bracket", "Expected ']' but found")
        Ast::BracketAccess.new(object:, key:, position: start_of(key_token), span: reaching(object, close))
      end

      def property(object)
        name = peek
        unless PROPERTY_NAMES.include?(name.type)
          refuse("expected_property_name", "Expected property name after '.' but found #{describe(name)}", name)
        end
        advance
        Ast::PropertyAccess.new(object:, property: name.value, position: start_of(name), span: reaching(object, name))
      end

      # The type name is an identifier matched against the seven names, so
      # each stays usable as a variable, a property and an object key.
      def cast(expression)
        name = expect(:identifier, "expected_type_name", "Expected a type name after '::' but found")
        unless CAST_TYPE_NAMES.include?(name.value)
          refuse("unknown_cast_type",
                 "Unknown cast type '#{name.value}' - expected one of: #{CAST_TYPE_NAMES.join(", ")}", name)
        end
        Ast::Cast.new(expression:, type_name: name.value, position: start_of(name), span: reaching(expression, name))
      end
    end
    private_constant :Postfix
  end
end
