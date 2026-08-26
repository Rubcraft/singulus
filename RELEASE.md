# Release checklist

Singulus delegates repository initialization, commits, branches, version-control operations, and release-tag creation to the Rubcraft Toolkit. This repository intentionally does not duplicate those commands.

Before publishing a Singulus release:

1. Update `Singulus::VERSION` and `CHANGELOG.md`.
2. Run `bundle exec rubocop --parallel`.
3. Run `COVERAGE=true bundle exec rspec`.
4. Run `bundle exec rake build` and inspect the generated gem.
5. Confirm the target version does not already exist on RubyGems.org.
6. Confirm RubyGems Trusted Publishing is configured for `.github/workflows/release.yml` and the GitHub environment `release`.
7. Use the Rubcraft Toolkit release flow to apply the repository/version-control changes and create the matching release tag.
8. Confirm the GitHub Actions `verify` job passes before the `publish` environment is approved.

`the internal runtime hardening layer` is Ruby-level hardening, not a process-security sandbox. Enable runtime mode during application boot before extension or untrusted code can capture constructor-derived `Proc` objects.
