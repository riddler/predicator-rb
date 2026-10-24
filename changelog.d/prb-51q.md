### Added

* The value domain: `Predicator::UNDEFINED` (an absence, distinct from `nil`, which is null), and the immutable values `Predicator::Date`, `Predicator::DateTime` (an instant in UTC to the microsecond) and `Predicator::Duration` (eight integer units). Integers and floats stay Ruby's `Integer` and `Float`, so `1` and `1.0` stay distinct.
* The error values `Predicator::ParseError`, `Predicator::EvaluationError`, `Predicator::TypeMismatchError` and `Predicator::UndefinedVariableError`, each with a `type` and a `reason`, a `message`, and a `Predicator::Position` (line and column) where one is known; and `Predicator::Error`, the exception that carries one.
* `Predicator::Result`, the value a call answers: `ok?`, `value` and `error`.
* `require "predicator/tagged"` loads `Predicator::Tagged`, a codec for the conformance corpus's tagged JSON encoding: `decode("[1.0]")` and `encode([1.0])` answer a `Predicator::Result`, and `decode!` and `encode!` raise `Predicator::Error` instead.
