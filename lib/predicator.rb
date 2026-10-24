# frozen_string_literal: true

require_relative "predicator/version"
require_relative "predicator/values"
require_relative "predicator/errors"
require_relative "predicator/result"
require_relative "predicator/evaluator"
require_relative "predicator/lexer"
require_relative "predicator/parser"
require_relative "predicator/emitter"

# A safe, non-evaluating condition language for end users.
#
# The value domain is Ruby's own values where they fit - nil (null), true and
# false, Integer and Float (kept apart), String, Array (a list) and Hash with
# String keys (a map) - plus {Predicator::UNDEFINED}, {Predicator::Date},
# {Predicator::DateTime} and {Predicator::Duration}. The codec for the
# conformance corpus's tagged encoding is loaded on its own, with
# `require "predicator/tagged"`.
module Predicator
  # Compiles an expression's source to the instruction list the evaluator
  # runs. The operands are predicator values: a date literal is a
  # {Predicator::Date}, a decimal a Float, `undefined`
  # {Predicator::UNDEFINED}.
  #
  # A source that does not compile answers a failed result carrying a
  # {Predicator::ParseError}: the first refusal the scan, the parse or the
  # emit met, with its reason, the reference's message where the reference
  # has one, and its position. A statement (an assignment, an `if`, a
  # `while`) is not an expression and is refused; {compile_program} compiles
  # one.
  #
  # @example
  #   Predicator.compile("score > 85").value
  #   # => [["load", "score"], ["lit", 85], ["compare", "GT"]]
  #
  # @param source [String] the text, in UTF-8 or an encoding that converts
  #   to it
  # @return [Result] the instruction list, or the {ParseError}
  # @raise [ArgumentError] when source is not a String, or is not text in
  #   its encoding
  def self.compile(source) = compiled(source) { |tokens| Parser.parse(tokens) }

  # Compiles a program's source, one or more statements separated by `;`, to
  # the instruction list the evaluator runs in statement mode. A statement is
  # an assignment to a location (an identifier, a property access or a
  # bracket access), an `if` with an optional `else` or `else if`, a
  # `while`, or an expression whose value is discarded. Every statement
  # leaves the stack as it found it: an assignment ends in a `store`, an
  # expression in a `pop`.
  #
  # A source that does not compile answers a failed result carrying a
  # {Predicator::ParseError}, as {compile} does.
  #
  # @example
  #   Predicator.compile_program("x = 1; x + 1").value
  #   # => [["lit", "x"], ["lit", 1], ["store", 1], ["load", "x"], ["lit", 1], ["add"], ["pop"]]
  #
  # @param source [String] the text, in UTF-8 or an encoding that converts
  #   to it
  # @return [Result] the instruction list, or the {ParseError}
  # @raise [ArgumentError] when source is not a String, or is not text in
  #   its encoding
  def self.compile_program(source) = compiled(source, program: true) { |tokens| Parser.parse_program(tokens) }

  # Scans the source, parses its tokens with the block and emits the tree,
  # answering the first refusal of the three.
  def self.compiled(source, program: false)
    tokens = Lexer.tokenize(text_of(source))
    tree = tokens.is_a?(Lexer::Refusal) ? tokens : yield(tokens)
    entries = if tree.is_a?(Lexer::Refusal) then tree
              elsif program then Emitter.emit_program(tree)
              else Emitter.emit(tree)
              end
    return Result.failure(entries.error) if entries.is_a?(Lexer::Refusal)

    Result.ok(entries.map(&:instruction))
  end

  # The source as valid UTF-8: bytes with no encoding of their own (binary
  # or US-ASCII) are read as UTF-8, and text in any other encoding is
  # converted to it.
  def self.text_of(source)
    raise ArgumentError, "a source is a String, not #{source.class}" unless source.is_a?(String)

    text = if [Encoding::BINARY, Encoding::US_ASCII].include?(source.encoding)
             source.dup.force_encoding(Encoding::UTF_8)
           else
             source.encode(Encoding::UTF_8)
           end
    return text if text.valid_encoding?

    raise ArgumentError, "a source is text, and this one is not valid #{text.encoding}"
  rescue EncodingError => e
    raise ArgumentError, "a source is text that converts to UTF-8: #{e.message}"
  end
  private_class_method :compiled, :text_of
end
