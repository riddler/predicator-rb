# frozen_string_literal: true

# What the reference's JSON reader answers for texts it refuses, for the
# JSON.parse tests to hold this package's answers against.
module JsonReferenceAnswers
  # Texts the reference's JSON reader (Elixir 1.18.3's JSON.decode, as
  # predicator-ex v9.5.0 describes its errors) refuses, with the fault it
  # reports, asked of it for each text.
  FAULTS = {
    "[1]  x" => "unexpected byte 0x20 at position 3",
    "1 x" => "unexpected byte 0x20 at position 1",
    "true false" => "unexpected byte 0x20 at position 4",
    "{\"a\":1} {" => "unexpected byte 0x20 at position 7",
    "[1,2] ]" => "unexpected byte 0x20 at position 5",
    "[1]x" => "unexpected byte 0x78 at position 3",
    "\"\xC3x\"" => "unexpected byte 0x78 at position 2",
    "\"\xE2\x82\"" => "unexpected byte 0x22 at position 3",
    "\"\xED\xA0\x80\"" => "unexpected byte 0xA0 at position 2",
    "\"\xF0\x9F\x98\"" => "unexpected byte 0x22 at position 4",
    "\"\x80\"" => "unexpected byte 0x80 at position 1",
    "\"\xFF\"" => "unexpected byte 0xFF at position 1",
    "\"\xC0\x80\"" => "unexpected byte 0xC0 at position 1",
    "\"\xC1\xBF\"" => "unexpected byte 0xC1 at position 1",
    "\"\xE0\x80\x80\"" => "unexpected byte 0x80 at position 2",
    "\"\xE0\x9F\x80\"" => "unexpected byte 0x9F at position 2",
    "\"\xF4\x90\x80\x80\"" => "unexpected byte 0x90 at position 2",
    "\"\xF5\x80\"" => "unexpected byte 0xF5 at position 1",
    "\"\xF0\x80\x80\x80\"" => "unexpected byte 0x80 at position 2",
    "\"\xC3" => "unexpected end of input at position 2",
    "\"\xE2\x82" => "unexpected end of input at position 3",
    "[\xC3\xA9]" => "unexpected byte 0xC3 at position 1",
    "\"\xC3\xA9\x80\"" => "unexpected byte 0x80 at position 3",
    "\"\\u12\"" => "unexpected end of input at position 6",
    "\"\\ud800\"" => "unexpected end of input at position 8",
    "\"\\uD800\"" => "unexpected end of input at position 8",
    "\"\\ud800A\"" => "unexpected end of input at position 9",
    "[\"\\u1\"]" => "unexpected end of input at position 7",
    "\"\\u" => "unexpected end of input at position 3",
    "\"\\u00" => "unexpected end of input at position 5",
    "[\"\\ud800\", 1]" => "unexpected end of input at position 13",
    "\"\\ud800\\\"\"" => "unexpected end of input at position 10",
    "\"\\ud800\\n\"" => "unexpected end of input at position 10",
    "\"\\ud800\\u12\"" => "unexpected end of input at position 12",
    "\"\\uZZ\"" => "unexpected end of input at position 6",
    "\"\\uG\"" => "unexpected end of input at position 5",
    "\"\\ud8" => "unexpected end of input at position 5",
    "\"\\ud800abcdef\"" => "unexpected byte 0x61 at position 7",
    "\"\\ud800\\\\uabcd\"" => "unexpected byte 0x5C at position 7",
    "\"\\q" => "unexpected byte 0x71 at position 2",
    "\"\\" => "unexpected end of input at position 2",
    "\"a\x01" => "unexpected byte 0x01 at position 2",
    "\"\\q\"" => "unexpected byte 0x71 at position 2",
    "[1 2]" => "unexpected byte 0x32 at position 3",
    "-" => "unexpected end of input at position 1",
    "1." => "unexpected end of input at position 2",
    "1.e1" => "unexpected byte 0x65 at position 2",
    "01" => "unexpected byte 0x31 at position 1",
    "-a" => "unexpected byte 0x61 at position 1",
    "1e" => "unexpected end of input at position 2",
    "1e+" => "unexpected end of input at position 3",
    "nul" => "unexpected end of input at position 3",
    "tru" => "unexpected end of input at position 3",
    "[" => "unexpected end of input at position 1",
    "{" => "unexpected end of input at position 1",
    "{\"a\":}" => "unexpected byte 0x7D at position 5",
    "{\"a\" 1}" => "unexpected byte 0x31 at position 5",
    "{1:2}" => "unexpected byte 0x31 at position 1",
    "" => "unexpected end of input at position 0",
    "  " => "unexpected end of input at position 2",
    "[1,]" => "unexpected byte 0x5D at position 3",
    "not json" => "unexpected byte 0x6F at position 1"
  }.freeze

  # Texts it refuses as a sequence it cannot read, with the offset where
  # the sequence starts.
  SEQUENCES = {
    "\"\\udc00x\"" => 1,
    "\"\\u12G4\"" => 1,
    "[\"\\u12\", 1]" => 2,
    "\"\\ud800\\u0041\"" => 1,
    "\"\\ud800\\ud800\"" => 1,
    "\"\\ud800\\uZZZZ\"" => 1,
    "[\"\\udc00\"]" => 2,
    "\"a\\uDFFF\"" => 2,
    "\"\\uZZZZ\"" => 1,
    "\"\\ud800\\udc0Z\"" => 1,
    "\"\\u12\x01\"" => 1,
    "\"\\ud800\\u12345\"" => 1,
    "\"\\ud80\"x" => 1,
    "1e400" => 0,
    "-1e400" => 0,
    "[1.5e999]" => 1
  }.freeze
end
