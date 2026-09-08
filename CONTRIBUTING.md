# Contributing to Singulus

Thanks for helping improve Singulus.

## Development

Use the Rubcraft Toolkit for repository/worktree setup and version-control operations. Once the project is prepared:

1. Run `bundle install`.
2. Run `bundle exec rubocop --parallel`.
3. Run `bundle exec rspec`.
4. Add tests for behavior changes.
5. Update `CHANGELOG.md` under `[Unreleased]` for user-visible changes.

Please keep public API changes backward-compatible unless a breaking change is explicitly planned and documented.

## API documentation

Document supported APIs with YARD, including parameter/return types, policy
errors (using the public `Singulus::Error`), and examples where useful. Keep
private implementation constants out of the public reference. Installed class
methods use `@!method` on the pattern module as their canonical documentation;
implementation methods link to that contract.

Run `bundle exec rake yard` and inspect `doc/index.html` after changes.
Use `bundle exec yard stats --list-undoc` to inspect documentation coverage.

## Spec organization

Keep public behavior tests grouped by responsibility: `configuration_spec.rb`,
`singleton_spec.rb`, `multiton_spec.rb`, `multiton/retention_spec.rb`,
`public_api_spec.rb`, and `security/runtime_hardening_spec.rb`. Shared Multiton
setup lives in `support/multiton_helpers.rb` and is included explicitly. Place
new edge cases alongside their behavior rather than in coverage-only files.

Run `COVERAGE=true bundle exec rspec` to enforce line and branch thresholds.
Runtime guards remain installed for the process lifetime; run spec files
individually when changing security setup to check that they stand alone.
