# encoding: UTF-8
#--
# This file is automatically generated. Do not modify it.
# Generated by: oedipus_lex version 2.5.0.
# Source: lib/predicator/lexer.rex
#++

class Predicator::Lexer
  require 'strscan'

  SPACE      = /[ \t\r\n]/
  LPAREN     = /\(/
  RPAREN     = /\)/
  TRUE       = /true\b/
  FALSE      = /false\b/
  BANG       = /!/
  DOT        = /\./
  AND        = /and\b/
  OR         = /or\b/
  EQ         = /=/
  GT         = />/
  INTEGER    = /[+-]?\d(_?\d)*\b/
  STRING     = /(["'])(?:\\?.)*?\1/
  IDENTIFIER = /[a-z][A-Za-z0-9_]*\b/

  class LexerError < StandardError ; end
  class ScanError < LexerError ; end

  attr_accessor :lineno
  attr_accessor :filename
  attr_accessor :ss
  attr_accessor :state

  alias :match :ss

  def matches
    m = (1..9).map { |i| ss[i] }
    m.pop until m[-1] or m.empty?
    m
  end

  def action
    yield
  end

  attr_accessor :old_pos

  def column
    idx = ss.string.rindex("\n", old_pos) || -1
    old_pos - idx - 1
  end

  def scanner_class
    StringScanner
  end unless instance_methods(false).map(&:to_s).include?("scanner_class")

  def parse str
    self.ss     = scanner_class.new str
    self.lineno = 1
    self.state  ||= nil

    do_parse
  end

  def parse_file path
    self.filename = path
    open path do |f|
      parse f.read
    end
  end

  def location
    [
      (filename || "<input>"),
      lineno,
      column,
    ].compact.join(":")
  end

  def next_token

    token = nil

    until ss.eos? or token do
      self.lineno += 1 if ss.peek(1) == "\n"
      self.old_pos = ss.pos
      token =
        case state
        when nil then
          case
          when ss.skip(/#{SPACE}/) then
            # do nothing
          when text = ss.scan(/#{LPAREN}/) then
            action { [:LPAREN, text] }
          when text = ss.scan(/#{RPAREN}/) then
            action { [:RPAREN, text] }
          when text = ss.scan(/#{TRUE}/) then
            action { [:TRUE, text] }
          when text = ss.scan(/#{FALSE}/) then
            action { [:FALSE, text] }
          when text = ss.scan(/#{BANG}/) then
            action { [:BANG, text] }
          when text = ss.scan(/#{DOT}/) then
            action { [:DOT, text] }
          when text = ss.scan(/#{AND}/) then
            action { [:AND, text] }
          when text = ss.scan(/#{OR}/) then
            action { [:OR, text] }
          when text = ss.scan(/#{EQ}/) then
            action { [:EQ, text] }
          when text = ss.scan(/#{GT}/) then
            action { [:GT, text] }
          when text = ss.scan(/#{INTEGER}/) then
            action { [:INTEGER, text] }
          when text = ss.scan(/#{STRING}/) then
            action { [:STRING, text[1...-1]] }
          when text = ss.scan(/#{IDENTIFIER}/) then
            action { [:IDENTIFIER, text] }
          else
            text = ss.string[ss.pos .. -1]
            raise ScanError, "can not match (#{state.inspect}) at #{location}: '#{text}'"
          end
        else
          raise ScanError, "undefined state at #{location}: '#{state}'"
        end # token = case state

      next unless token # allow functions to trigger redo w/ nil
    end # while

    raise LexerError, "bad lexical result at #{location}: #{token.inspect}" unless
      token.nil? || (Array === token && token.size >= 2)

    # auto-switch state
    self.state = token.last if token && token.first == :state

    token
  end # def next_token
    def do_parse; end
end # class