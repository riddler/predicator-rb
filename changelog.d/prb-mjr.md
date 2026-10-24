### Added

* `Predicator.compile(source)` compiles an expression to the instruction list the evaluator runs, and `Predicator.compile_program(source)` compiles one or more statements (assignments, `if`, `while`, expressions) separated by `;`. Each answers a `Predicator::Result`: the list, its operands predicator values (`Predicator.compile("x > 1").value` is `[["load", "x"], ["lit", 1], ["compare", "GT"]]`), or a `Predicator::ParseError` with its reason, message and position. A source that is not a String, or not valid text in its encoding, raises `ArgumentError`.
* A decimal literal too large for a finite Float is refused with the reason `number_out_of_range`, and compiling any source prints no warning.
