# Predicator

[![MIT License][badge_license_url]](LICENSE)
[![CI][badge_ci_url]](https://github.com/riddler/predicator-rb/actions/workflows/ci.yml)
[![Gem Version][badge_version_url]](https://rubygems.org/gems/predicator)

A safe, non-evaluating condition language for end users, for Ruby. A condition
is written as text, such as `score > 85 and 2 in items`, compiled to a flat
list of stack-machine instructions and run against a context of variables. No
Ruby is ever evaluated: the text is read by a lexer and a parser of this
package, and the instructions are run by an evaluator that can do only what
the instruction set says. The language, the instruction set and the answers
are wire-compatible with the Elixir reference implementation,
[predicator-ex](https://github.com/riddler/predicator-ex), and the gem is
checked against that implementation's conformance corpus.

## Why Predicator

A rule an end user writes has to be decided by code the user did not write,
and often in more than one place. Passing the text to `eval` hands the user
the whole interpreter; a hand-rolled parser per place lets the copies drift
apart. Predicator gives one small language with a defined set of operations,
a defined answer for every operand a rule can meet (an error value, never a
crash), and a shared corpus that every implementation of it must pass. A
condition compiled in one implementation can be run by another, because the
instruction list is plain data.

## Install

Add `predicator` to your Gemfile:

```ruby
gem "predicator", "~> 2.0"
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install predicator

## Basic usage

```ruby
require "predicator"

# Compile once: the instruction list is plain data you can store or send
compiled = Predicator.compile("score > 85 and 2 in items")
compiled.value
# => [["load", "score"], ["lit", 85], ["compare", "GT"], ["jump_if_falsy_or_pop", 4],
#     ["lit", 2], ["load", "items"], ["in"]]

# Run it against a context: a Hash keyed by Strings
context = { "score" => 90, "items" => [1, 2, 3] }
Predicator.evaluate(compiled.value, context).value   # => true

# Or hand evaluate the source and let it compile
Predicator.evaluate("a.b + 1", { "a" => { "b" => 2 } }).value   # => 3

# A statement program answers the context it leaves
Predicator.execute("x = 1; y = x + 2").value        # => {"x" => 1, "y" => 3}

# A host function is passed per call, by name
double = ->(n) { n * 2 }
Predicator.evaluate("double(x)", { "x" => 4 }, functions: { "double" => double }).value   # => 8

# The bang variants answer the value itself, or raise Predicator::Error
Predicator.evaluate!("score > 85", { "score" => 90 })   # => true
```

## The result and error values

Every entry point answers a `Predicator::Result`: `ok?`, `value` and `error`.
A successful result has `error == nil` and a failed one has `value == nil`, so
read `ok?` and not the value: `nil` is predicator's null, and a successful
result may hold it. Nothing about the source or the program raises: a source
that does not compile, a run that stops and a value outside the language's
domain all answer a failed result.

```ruby
result = Predicator.evaluate("x / 0", { "x" => 1 })
result.ok?                 # => false
result.error.type          # => "EvaluationError"
result.error.reason        # => "division_by_zero"
result.error.message       # => "divide was given a zero divisor"
```

A call that compiles or runs answers one of four error values, each with a
`type` (its class's name), a `reason`, a `message` and a `position` (a
`Predicator::Position` with `line` and `column`, or `nil` where none is
known):

- `Predicator::ParseError`: a source that does not compile. It always has a
  position.
- `Predicator::EvaluationError`: a run that stopped, such as a division by
  zero, an unknown instruction or a host function that raised.
- `Predicator::TypeMismatchError`: an operand an operation refused on its
  type. Its reason is the operation.
- `Predicator::UndefinedVariableError`: a variable the context does not bind,
  when the run's answer depends on it.

The `type` and the `reason` are what the conformance corpus matches; the
`message` is for a person and may change. Each entry point has a bang variant
(`compile!`, `compile_program!`, `evaluate!`, `execute!`, `execute_value!`,
`parse!`, `parse_duration!`) that answers the value or raises
`Predicator::Error`, whose `error` is the same error value.

Two things still raise. A bug in the call itself (an argument of the wrong
kind, an unknown option, a source that is not valid text) raises
`ArgumentError`. And an exception that is not a `StandardError` (an
`Interrupt`, a `SystemExit`, a `NoMemoryError`) raised by host code a run
calls propagates unchanged.

### The entry points

| Call | Answers, in the result |
|---|---|
| `Predicator.compile(source)` | the instruction list of an expression, or a `ParseError` |
| `Predicator.compile_program(source)` | the instruction list of one or more statements separated by `;`, or a `ParseError` |
| `Predicator.evaluate(program, context = {}, **options)` | an expression's value; `program` is an instruction list or source |
| `Predicator.execute(program, context = {}, **options)` | the context at halt, a Hash holding every write; the context passed is never changed |
| `Predicator.execute_value(program, context = {}, **options)` | the pair `[value, context]` of the last expression statement's value and the context at halt |
| `Predicator.parse(source)` | the root of the syntax tree |
| `Predicator.parse_duration(text)` | a `Predicator::Duration` read from text such as `"1h30m"` |
| `Predicator.isa_version` | the instruction-set version the build emits and runs, 6 |

`parse` answers the syntax tree's root. The node classes and the tree's shape
are not part of the public surface and may change in a minor version.

### Options

The options of a run are keywords of the call that runs it. Nothing is
configured globally.

- `functions:` a Hash of String name to a callable, the host's functions for
  this run. A function is called with the call's arguments only, first
  argument first, and nothing else (no context argument). Each argument is a
  copy, so nothing the function does to one changes the context. The counts of
  arguments a function takes are read from its parameters. It refuses by
  raising a `StandardError`, which fails the run with an `EvaluationError`. Its
  answer is checked against the value domain, and an answer outside it fails
  the run; the answer is not copied. A name here shadows the library function
  of the same name, for this run only. `{}` by default.
- `clock:` a callable answering the current time as a `Predicator::DateTime`,
  read at most once per run and only when the program reads the time. The
  system's real-time clock by default. A clock that answers anything else, or
  raises a `StandardError`, fails the run with the reason `clock_failed`.
- `on_unbound:` what a load of a variable the context does not bind does:
  `:undefined` (the default) pushes `Predicator::UNDEFINED` and fails the run
  with an `UndefinedVariableError` only if undefined is the answer; `:error`
  fails the run at the load.
- `loop_budget:` how many back edges one run may take, an Integer of at least
  0, 10_000 by default. A run that finds it spent fails with the reason
  `loop_budget_exceeded`.

A run that stops answers its error value and no partial context: `execute` and
`execute_value` answer neither a context nor a value for a run that stopped.

### The value domain

A context, and any literal operand of an instruction list you built, is
checked against the value domain before anything runs. The domain is Ruby's
own values where they fit: `nil` (null), `true` and `false`, `Integer` and
`Float` (kept apart, so `1` and `1.0` differ), `String`, `Array` (a list) and
`Hash` (a map, keyed by a String, an Integer, `true`, `false`, `nil` or
`Predicator::UNDEFINED`), plus `Predicator::UNDEFINED` (an absence, distinct
from `nil`), `Predicator::Date`, `Predicator::DateTime` (an instant in UTC to
the microsecond) and `Predicator::Duration` (eight integer units).

The root keys of a context are Strings: a Symbol key at the root fails the run
with an `EvaluationError` (reason `unsupported_host_value`) and is not
converted. The same reason refuses a value the domain has no member for (a
Symbol, a `Time`, any other object). A Float that is not finite
(`non_finite_number`), a list or map that contains itself (`cyclic_value`) and
lists and maps nested past 100 levels (`depth_limit_exceeded`) are refused the
same way. Equality, ordering and membership walk nested lists and maps without
recursing, so a value nested to any depth inside those limits is compared
without overflowing the stack.

`require "predicator/tagged"` loads `Predicator::Tagged`, a codec for the
conformance corpus's tagged JSON encoding, which keeps what a JSON round trip
loses (dates, instants, durations, undefined): `decode` and `encode` answer a
`Predicator::Result`, and `decode!` and `encode!` raise `Predicator::Error`.
A failed codec result carries a `Predicator::Tagged::CodecError`, which has a
`type`, a `reason` and a `message` and no position.

## Compatibility

- **Ruby 3.3 or later** (`required_ruby_version` in the gemspec). CI runs the
  test suite on every Ruby minor from 3.3 up to the version `mise.toml` pins,
  and the full quality gate on that pinned version.
- **No runtime dependencies.** The gemspec declares none; `strscan` and `json`
  are default gems that ship with Ruby.
- **No shared mutable state.** There is no global configuration, no monkey
  patch and no class-level or module-level mutable state. Host functions and
  clocks are passed per call, and a call reads only its arguments, so nothing
  is shared between calls.
- **Instruction set:** version 6, answered by `Predicator.isa_version`.

## Conformance

The language is defined by the reference implementation's conformance corpus,
vendored under `conformance/` at a release tag of
[predicator-ex](https://github.com/riddler/predicator-ex). `conformance/SOURCE.json`
names the tag, the commit and the corpus hash; at this head they are the tag
`v9.5.0`, the commit `fd7fb0157e5a314086197187b4c5192bae31720e`, the
instruction-set version 6 and the hash
`sha256:ddc5cf824b06b4899e1bd4166263a1ee07016ff239216e029b9276ac17243975`.

The corpus has two surfaces: the **evaluator** runs an instruction list against
a context, and the **compiler** compiles a source to the instruction list the
corpus expects. Cases are grouped in nine cumulative tiers, and a claim of
tier N says every case of that surface in tiers 1 through N passes.
`conformance/registry.json` records the claims and one entry per passing case.
At this head:

- The evaluator claims tier 9, with 262 entries. The corpus holds 267 evaluator
  cases; the other 5 carry the `retired` feature tag (they use an opcode the
  instruction-set version 6 retired), and a run that claims version 6 does not
  attempt them.
- The compiler claims tier 7, with 220 entries: every compiler case in the
  corpus, all of them in tiers 1 through 5 and 7. A case with no source text
  is not on the compiler surface.

No case is skipped. A case this package cannot pass is a defect to bring to
the reference, never an entry on a skip list. The counts are read from the
registry and the corpus, and you can re-derive them: the registry's `claims`
array and its `entries` (each `{case_id, surface, tier}`) hold the claims and
the passes, `conformance/manifest.json` holds the case count of each tier, and
`mise exec -- bundle exec rake registry` re-runs both surfaces and prints, per
surface, how many cases of the corpus have no entry (0 of 220 for the compiler,
5 of 267 for the evaluator at this head). `mise exec -- bundle exec rake` runs
the whole gate, which includes that check and fails if the registry and a run
made now disagree.

### Differences from the reference

Where the corpus is silent, the reference at the tag answers. These are the
places where this package's answer follows the reference's normative text
rather than its code, follows its code where its text is silent, or has no
counterpart in the reference:

- **A duration is the map of its eight units, from any origin.** The
  reference's instruction-set document (`docs/isa.md`, section 3) makes a
  duration a map of its eight units, `years` through `milliseconds`. A
  duration here reads and moves as that map whether it came from a literal, an
  opcode or the host: its unit names are its keys and any other key misses. A
  plain map handed where a duration is read (a relative date's operand) is
  read the same way, with an absent unit as 0.
- **Bracket access on a date or an instant** follows the reference's code,
  which its instruction-set prose does not state: a `Predicator::Date` or
  `Predicator::DateTime` takes a bracket access as a map would. A key that can
  be a map key (a String, an Integer, a boolean, null or undefined) misses and
  answers undefined; any other key is a `TypeMismatchError`.
- **A Float result that is not finite** (an overflow) is refused as an
  `EvaluationError` with the reason `non_finite_number`. The reference has no
  answer of its own there to follow.
- **A store through a date or an instant** is refused with the reason
  `not_a_container`. **A store through a duration** writes through the plain map
  of its eight units, the same reading the `object_set` instruction uses.
- **The parser bounds nesting.** The reference's parser has no bound. This
  parser refuses a source that nests 400 levels or more (the whole expression
  counts as the first level), with the reason `nesting_depth_exceeded`. On a
  stack too small to reach that limit, as a Fiber's default stack is (each
  request of an asynchronous server runs in one), the parser refuses at a
  lower depth under the same reason rather than raising `SystemStackError`.
  The emitter has the same refusal for a tree whose walk runs out of stack.
- **The host function contract is arguments only.** The reference passes a
  function its arguments and the context, and takes an ok or error tuple. Here
  a function takes the arguments, answers its value and refuses by raising.
- **The options differ.** The reference's `protected_roots` option (roots a
  statement program may not store into) is not offered, nor are its
  `providers`, `builtins`, `host`, `positions` and `segment_positions`
  options; an unknown keyword raises
  `ArgumentError`. `functions:`, `on_unbound:` and `loop_budget:` are in both.
  `clock:` is this package's own: the reference reads the system clock, and
  here the host passes one per call.

## Upgrading from 1.x

Version 2.0.0 is a different implementation under the same gem name. It is a
breaking release, not an upgrade path for 1.x code, and the 1.x API is gone.
To stay on 1.x, pin it (1.x releases stay installable from rubygems.org; the
last is 1.2.1):

```ruby
gem "predicator", "~> 1.2"
```

The 1.x source lives in the
[riddler/predicator](https://github.com/riddler/predicator) repository under
`impl/rb`. To move to 2.0:

| 1.x | 2.0 |
|---|---|
| `Predicator.evaluate(source, context = {})` answered the value | `Predicator.evaluate(source, context)` answers a `Predicator::Result`; `evaluate!` answers the value and raises `Predicator::Error` |
| `Predicator.compile(source)` answered an instruction list | `Predicator.compile(source)` answers a `Result` holding an instruction list; `compile!` answers the list |
| `Predicator.evaluate_instructions(instructions, context)` | gone: `Predicator.evaluate(instructions, context)` takes an instruction list or source |
| `Predicator.parse(source)` answered a `Predicator::AST` node with `to_instructions`, `to_s`, `to_dot` and `Enumerable` | `Predicator.parse(source)` answers a `Result` holding the tree's root; its node classes and shape are not public, and the node methods and the visitors are gone |
| `Predicator::Parser`, `Predicator::Evaluator` (with `stack` and `result`), `Predicator::Context` and `Predicator::AST` | gone: they are private to the package, and a context is a plain Hash |
| a source that did not parse raised from the parser | a source that does not compile answers a failed `Result` with a `ParseError` |
| a context given as a Hash with String or Symbol keys, or as keywords (`evaluate "score > 1", score: 2`) | a Hash passed as the second argument, keyed by Strings; a Symbol key at the root fails the run with `unsupported_host_value`, and keywords are the run's options |
| a variable the context did not bind read as `nil`, so a comparison with it answered `false` | the run's answer is undefined, and fails with an `UndefinedVariableError` when undefined is the answer; `on_unbound: :error` fails at the load |
| 1.x instruction lists | a list that uses an opcode 2.0 does not have (such as `jfalse`, `to_int` or `array`) fails with `unknown_instruction`; a list of only `lit`, `load`, `not` and `compare` runs, under 2.0's rules for the comparison and the unbound variable above; recompile the source with 2.0 either way |
| a custom function, a clock or a limit: none | `functions:`, `clock:`, `on_unbound:` and `loop_budget:` keywords |
| statement programs: none | new in 2.0: `compile_program`, `execute` and `execute_value` |

Store the condition's source text, not its 1.x instruction list, and compile
it with 2.0. The instruction list 2.0 emits is the reference's instruction set
version 6, which is the same plain data in every implementation of it.

## Documentation

- Look up
  - Every public method and class carries a YARD doc comment in `lib/`:
    the `Predicator` module's entry points, the values, the error values and
    `Predicator::Result`, and `Predicator::Tagged`.
  - [The instruction-set reference](https://github.com/riddler/predicator-ex/blob/v9.5.0/docs/isa.md):
    the instructions, the value space and the refusals, which this package
    implements, read at the corpus tag.
  - [The changelog](CHANGELOG.md): what changed in each version.
  - [The conformance corpus](conformance/README.md): what is vendored, from
    where, and what is this repository's own.
- Understand
  - [Why a predicate language of its own](https://github.com/riddler/predicator-ex/blob/v9.5.0/docs/explanation/why-a-predicate-language-of-its-own.md):
    why not `eval`, and why not a general-purpose language.
  - [Embedding Predicator](https://github.com/riddler/predicator-ex/blob/v9.5.0/docs/guides/embedding.md)
    and [custom functions](https://github.com/riddler/predicator-ex/blob/v9.5.0/docs/guides/custom-functions.md),
    in the reference's terms (read the function contract above for this
    package's).

## Development

```bash
mise install                          # the Ruby that mise.toml pins
mise exec -- bundle install           # the dev tools
mise exec -- bundle exec rake         # the gate: rubocop, the corpus and registry checks, the tests
```

## Contributing

Bug reports and pull requests are welcome on GitHub at
https://github.com/riddler/predicator-rb.

## License

MIT, see `LICENSE`.

<!-- BADGES -->
[badge_license_url]: https://img.shields.io/badge/license-MIT-brightgreen.svg?cacheSeconds=3600?style=flat-square
[badge_ci_url]: https://github.com/riddler/predicator-rb/actions/workflows/ci.yml/badge.svg
[badge_version_url]: https://badge.fury.io/rb/predicator.svg
