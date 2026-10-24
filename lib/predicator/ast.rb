# frozen_string_literal: true

module Predicator
  # The syntax tree the parser builds: the reference's node kinds, with the
  # reference's fields, as immutable values.
  #
  # Every node carries both of the reference's two kinds of source metadata,
  # where the reference's parser carries one or the other per parse. The
  # position is the {Predicator::Position} of the token that defines the
  # node, which is not always its leftmost token: an operator node points at
  # its operator, an access node at the property or the key rather than the
  # punctuation before it, a cast at its type name, a relative date written
  # after its duration at the word `ago` or `from`. The span is the source
  # the node covers, a {Lexer::Span} with an exclusive end. A parenthesized
  # expression keeps its node's position and widens its span to the
  # parentheses.
  #
  # The kinds and their fields follow the reference's syntax tree:
  #
  # - {Literal}: a number, a boolean, null, undefined, a date or a datetime;
  #   its value is the predicator value ({Predicator::UNDEFINED}, nil, an
  #   Integer, a Float, a {Predicator::Date}, a {Predicator::DateTime}). A
  #   negative number is a {Unary} minus over a literal, never a negative
  #   literal.
  # - {StringLiteral}: a string and the quote it was written with
  #   (`:double` or `:single`).
  # - {Identifier}, {Comparison}, {Arithmetic}, {Membership}, {Unary},
  #   {LogicalAnd}, {LogicalOr}, {LogicalNot}, {ListLiteral},
  #   {ObjectLiteral} (whose entries are `[ObjectKey, node]` pairs),
  #   {FunctionCall}, {BracketAccess}, {PropertyAccess}, {Cast},
  #   {Duration} (whose units are `[amount, suffix]` pairs in the order
  #   written, a fraction already expanded into whole units) and
  #   {RelativeDate}.
  # - The statement kinds a program holds: {Assignment}, {If} (an `else if`
  #   is an else {Block} holding one {If}, which borrows that `if`'s
  #   position and span), {While}, {Block} and {Program}. Any expression
  #   node also stands as a statement.
  #
  # The operators are the reference's: comparison `:gt`, `:lt`, `:gte`,
  # `:lte`, `:equal_equal`, `:ne`, `:strict_eq`, `:strict_ne`; arithmetic
  # `:add`, `:subtract`, `:multiply`, `:divide`, `:modulo`; membership
  # `:in`, `:contains`; unary `:minus`, `:bang`; relative-date directions
  # `:ago`, `:future` (written `from now`), `:next`, `:last`.
  #
  # The module is private to the package.
  module Ast
    # A node class with the fields given, then a position and a span.
    def self.node(*fields) = Data.define(*fields, :position, :span)
    private_class_method :node

    Literal = node(:value)
    StringLiteral = node(:value, :quote)
    Identifier = node(:name)
    Comparison = node(:operator, :left, :right)
    Arithmetic = node(:operator, :left, :right)
    Membership = node(:operator, :left, :right)
    Unary = node(:operator, :operand)
    LogicalAnd = node(:left, :right)
    LogicalOr = node(:left, :right)
    LogicalNot = node(:operand)
    ListLiteral = node(:elements)
    ObjectLiteral = node(:entries)
    ObjectKey = node(:name, :style)
    FunctionCall = node(:name, :arguments)
    BracketAccess = node(:object, :key)
    PropertyAccess = node(:object, :property)
    Cast = node(:expression, :type_name)
    Duration = node(:units)
    RelativeDate = node(:duration, :direction)
    Assignment = node(:target, :value)
    Block = node(:statements)
    If = node(:condition, :then_block, :else_block)
    While = node(:condition, :body)
    Program = node(:statements)
  end
  private_constant :Ast
end
