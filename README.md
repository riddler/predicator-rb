# Predicator

A safe, non-evaluating condition language for end users, for Ruby.

This is the 2.0.0 rewrite, in progress: the gem `predicator` is being
rebuilt as a compiler from a condition's source text to stack-machine
instructions plus an evaluator, wire-compatible with the Elixir reference
implementation, [predicator-ex](https://github.com/riddler/predicator-ex). The
head holds the package, its quality gate and the conformance corpus it is
checked against (`conformance/`, whose README says what is copied and from
where). The public entry points (`Predicator.compile`, `evaluate`, `execute`
and the rest) are documented in their doc comments in `lib/predicator.rb`;
the full README arrives with a later change.

The 1.x gem is a different implementation. Its source lives in the
[riddler/predicator](https://github.com/riddler/predicator) repository under
`impl/rb`, and 1.x releases stay installable from rubygems.org.

## Development

```bash
mise install                          # the Ruby that mise.toml pins
mise exec -- bundle install           # the dev tools
mise exec -- bundle exec rake         # the gate: rubocop, the corpus and registry checks, the tests
```

## License

MIT, see `LICENSE`.
