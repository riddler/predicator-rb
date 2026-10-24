### Upcoming

* (Nothing yet)


### 2.0.0 / 2026-10-24

A rewrite of the gem under its existing name, and a breaking release: the 1.x
API is gone. The gem now compiles and evaluates the condition language of the
Elixir reference implementation, [predicator-ex](https://github.com/riddler/predicator-ex),
with its instruction set version 6, and is checked against that
implementation's conformance corpus at the tag `v9.5.0`, vendored under
`conformance/` (`conformance/SOURCE.json` records the tag, its commit and the
corpus hash). It claims tier 9 of the corpus's evaluator surface and tier 7 of
its compiler surface (`conformance/registry.json`), with no case skipped. It
requires Ruby 3.3 or later and has no runtime dependencies. To stay on 1.x,
pin `gem "predicator", "~> 1.2"`; the README's "Upgrading from 1.x" maps each
1.x call to its 2.0 counterpart. The 1.x history, and the source of the 1.x
gem, live in the [riddler/predicator](https://github.com/riddler/predicator)
repository (`impl/rb`).

**Added**

* The value domain: `Predicator::UNDEFINED` (an absence, distinct from `nil`, which is null), and the immutable values `Predicator::Date`, `Predicator::DateTime` (an instant in UTC to the microsecond) and `Predicator::Duration` (eight integer units). Integers and floats stay Ruby's `Integer` and `Float`, so `1` and `1.0` stay distinct.
* The error values `Predicator::ParseError`, `Predicator::EvaluationError`, `Predicator::TypeMismatchError` and `Predicator::UndefinedVariableError`, each with a `type` and a `reason`, a `message`, and a `Predicator::Position` (line and column) where one is known; and `Predicator::Error`, the exception that carries one.
* `Predicator::Result`, the value a call answers: `ok?`, `value` and `error`.
* `require "predicator/tagged"` loads `Predicator::Tagged`, a codec for the conformance corpus's tagged JSON encoding: `decode("[1.0]")` and `encode([1.0])` answer a `Predicator::Result`, and `decode!` and `encode!` raise `Predicator::Error` instead.
* `Predicator.compile(source)` compiles an expression to the instruction list the evaluator runs, and `Predicator.compile_program(source)` compiles one or more statements (assignments, `if`, `while`, expressions) separated by `;`. Each answers a `Predicator::Result`: the list, its operands predicator values (`Predicator.compile("x > 1").value` is `[["load", "x"], ["lit", 1], ["compare", "GT"]]`), or a `Predicator::ParseError` with its reason, message and position. A source that is not a String, or not valid text in its encoding, raises `ArgumentError`.
* A decimal literal too large for a finite Float is refused with the reason `number_out_of_range`, and compiling any source prints no warning.
* `Predicator.evaluate(program, context, **options)` runs an expression, given as an instruction list or as source text, and answers its value; `Predicator.execute` runs a statement program and answers the context at halt; `Predicator.execute_value` answers the pair of the last expression statement's value and that context. A run that stops answers its error value and no context.
* `Predicator.parse(source)` answers an expression's syntax tree (its node classes are private and its shape is not a compatibility promise), `Predicator.parse_duration("1h30m")` answers a `Predicator::Duration` or an `EvaluationError` with the reason `invalid_duration_format`, and `Predicator.isa_version` answers 6.
* Every entry point that answers a `Predicator::Result` has a bang variant (`compile!`, `compile_program!`, `evaluate!`, `execute!`, `execute_value!`, `parse!`, `parse_duration!`) that answers the value or raises `Predicator::Error` carrying the error value.
* A run's options are keywords of the call: `functions:` (a Hash of String name to a callable, called with the arguments only, each a copy, refusing by raising), `clock:` (a callable answering a `Predicator::DateTime`; one that answers anything else, or raises, fails the run with an `EvaluationError` whose reason is `clock_failed`), `on_unbound:` (`:undefined` or `:error`) and `loop_budget:` (10000 back edges by default). Nothing is configured globally.
* A context, a literal operand or a host function's answer outside the value domain (a key that is not a String at the context's root, a Symbol or other object, a Float that is not finite, a list or map that contains itself or nests past 100 levels) fails the run with an `EvaluationError` (`unsupported_host_value`, `non_finite_number`, `cyclic_value`, `depth_limit_exceeded`) instead of raising.

**Changed**

* Breaking: Ruby 3.3 or later is required, where 1.x declared no Ruby version; stay on 1.x on an older Ruby.

**Removed**

* Breaking: the 1.x API is removed, and 1.x code does not run against 2.0. Pin `gem "predicator", "~> 1.2"` to stay on 1.x, or move each call as the README's "Upgrading from 1.x" says; store a condition's source text and compile it with 2.0 rather than reusing a 1.x instruction list.
