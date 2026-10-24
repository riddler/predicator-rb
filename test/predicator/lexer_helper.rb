# frozen_string_literal: true

# The scanner, reached as the compiler reaches it, and its answers in the
# shape the tokens transcript records them.
module LexerHelper
  LEXER = Predicator.const_get(:Lexer)
  REFUSAL = LEXER.const_get(:Refusal)

  def tokenize(source) = LEXER.tokenize(source)

  # The tokens' types, lines, columns, lengths and values, in order.
  def scanned(source)
    result = tokenize(source)
    flunk "#{source.inspect} was refused: #{result.error.message}" if result.is_a?(REFUSAL)
    result.map { |token| [token.type, token.line, token.column, token.length, token.value] }
  end

  # The refusal's reason, message, position and span, each position as
  # [line, column].
  def refusal(source)
    result = tokenize(source)
    flunk "#{source.inspect} scanned: #{result.map(&:type)}" unless result.is_a?(REFUSAL)
    error = result.error
    [error.reason, error.message, place(error.position), place(result.span.start), place(result.span.end)]
  end

  # What the scanner answers for a source, as a transcript row records it.
  def observed_row(source)
    result = tokenize(source)
    return refusal_row(source, result) if result.is_a?(REFUSAL)

    { "kind" => "tokens", "source" => source, "tokens" => result.map { |token| token_row(token) } }
  end

  private

  def place(position) = [position.line, position.column]

  def json_place(position) = { "column" => position.column, "line" => position.line }

  def token_row(token)
    row = { "column" => token.column, "length" => token.length, "line" => token.line, "type" => token.type.to_s }
    return row unless token.type == :string

    row.merge("end" => json_place(token.end_position), "quote" => token.quote.to_s)
  end

  def refusal_row(source, result)
    { "kind" => "refusal", "message" => result.error.message, "position" => json_place(result.error.position),
      "source" => source, "span" => { "end" => json_place(result.span.end), "start" => json_place(result.span.start) } }
  end
end
