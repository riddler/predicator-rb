# frozen_string_literal: true

require_relative "lexer_helper"

# The parser, reached as the compiler reaches it: the lexer's tokens in, a
# syntax tree or a refusal out.
module ParserHelper
  include LexerHelper

  PARSER = Predicator.const_get(:Parser)
  AST = Predicator.const_get(:Ast)

  # The expression's tree, or the refusal (the lexer's or the parser's).
  def parse(source)
    tokens = tokenize(source)
    tokens.is_a?(REFUSAL) ? tokens : PARSER.parse(tokens)
  end

  # The program's tree, or the refusal (the lexer's or the parser's).
  def parse_program(source)
    tokens = tokenize(source)
    tokens.is_a?(REFUSAL) ? tokens : PARSER.parse_program(tokens)
  end

  # A node as {#tree} writes it: an identifier, a literal, a string.
  def id(name) = [:identifier, name]
  def lit(value) = [:literal, value]
  def str(value, quote = :single) = [:string_literal, value, quote]
  def duration(*units) = [:duration, units]

  # The expression's tree with its positions and spans left out: each node
  # an array of its kind (the class name, in snake case) and its fields.
  def tree(source)
    node = parse(source)
    flunk "#{source.inspect} was refused: #{node.error.message}" if node.is_a?(REFUSAL)
    bare(node)
  end

  # The program's statements, each as {#tree} writes a node.
  def statements(source)
    program = parse_program(source)
    flunk "#{source.inspect} was refused: #{program.error.message}" if program.is_a?(REFUSAL)
    bare(program.statements)
  end

  # The refusal of an expression, or of a program, as [reason, message,
  # position, span start, span end], each place [line, column].
  def refused(source, program: false)
    result = program ? parse_program(source) : parse(source)
    flunk "#{source.inspect} parsed: #{bare(result).inspect}" unless result.is_a?(REFUSAL)
    [result.error.reason, result.error.message, *located_refusal(result)]
  end

  # A node's position and span, as [line, column] pairs.
  def located(node) = [place(node.position), place(node.span.start), place(node.span.end)]

  # Each source's tree (or program's statements), against the table's.
  def assert_trees(table, program: false)
    assert_equal(table, table.to_h { |source, _| [source, program ? statements(source) : tree(source)] })
  end

  # Each source's refusal, against the table's.
  def assert_refusals(table, program: false)
    assert_equal(table, table.to_h { |source, _| [source, refused(source, program:)] })
  end

  # The position and span of the node each path (a list of field names)
  # reaches from the source's tree, against the table's.
  def assert_located(source, table, program: false)
    root = program ? parse_program(source) : parse(source)
    assert_equal(table, table.to_h { |path, _| [path, located(follow(root, path))] })
  end

  # The node a path of field names and indexes reaches.
  def follow(node, path) = path.reduce(node) { |at, field| field.is_a?(Integer) ? at[field] : at.public_send(field) }

  def located_refusal(result) = [place(result.error.position), place(result.span.start), place(result.span.end)]

  def bare(value)
    case value
    when Array then value.map { |item| bare(item) }
    when *NODES then [kind(value), *value.to_h.except(:position, :span).values.map { |field| bare(field) }]
    else value
    end
  end

  NODES = AST.constants.map { |name| AST.const_get(name) }.grep(Class).freeze

  def kind(node) = node.class.name.split("::").last.gsub(/([a-z])([A-Z])/, '\1_\2').downcase.to_sym

  private :bare, :kind, :follow, :located_refusal
end
