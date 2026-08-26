# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project adheres to Semantic Versioning.

## [Unreleased]

### Fixed

- Completed the final RuboCop cleanup across Multiton and specs.
- Removed `refuse_coverage_drop`; coverage is enforced by absolute minimums of 95% line and 90% branch.

- Normalized RuboCop policy so local Rubcraft checks and GitHub CI enforce the same repository-local configuration.
- Fixed production-code indentation/alignment issues introduced during the `Singulus::Internal` refactor.
- Removed the redundant `thread` require.
- Added RubyGems MFA metadata.
- Moved development tooling declarations to Gemfile.
- Kept intentional reflection interception, internal ivar naming, Multiton complexity, and contract-style specs explicitly documented in RuboCop configuration.

- Added a small coverage buffer for safe mutation/reflection fallthrough paths and repeated runtime-hardening activation.

- Made RuboCop configuration explicit and repository-local for identical local/CI behavior.
- CI and release workflows now pass `.rubocop.yml` explicitly.
- Standardized the project on double-quoted Ruby strings.

- Added `bundler-audit` as a development dependency so Rubcraft's mandatory audit gate runs through the repository bundle.

- Fixed `InstanceGuard#clone` so it does not forward an implicit `freeze:` keyword to Ruby Singleton implementations that accept no arguments.
- Corrected standard-mode reflection coverage: reflective constructor access is intentionally available when local hardening is disabled.
- Corrected runtime-hardening coverage to distinguish blocked reflection gateways from safe non-gateway UnboundMethod binding.

- Added branch-focused behavior coverage for standard-mode fallthroughs, reflection guards, runtime-hardening negative paths, and valid Multiton retention branches.

- Corrected runtime Method composition specs to distinguish `Method#<<`/`Method#>>` from `Proc#<<` composition semantics.

- Expanded behavioral coverage for configuration normalization, public reflection guards, Multiton registry edge cases, forwarding semantics, standard-mode inheritance, and runtime Method composition.

- Corrected RSpec expectations for sealed constructor access.
- Corrected Multiton key-stabilization coverage to use genuinely mutable input under `frozen_string_literal`.
- Corrected Hash identifiers to be passed positionally under Ruby 3 keyword argument semantics.

## [0.1.0] - 2026-08-21

### Changed

- Reduced the public root API to `Singulus::Singleton`, `Singulus::Multiton`, `Singulus::Error`, `Singulus::VERSION`, and the configuration facade.
- Moved implementation classes, guards, configuration objects, and specialized exceptions behind a private `Singulus::Internal` namespace.
- Marked Multiton implementation constants (`RETENTIONS`, `Entry`, and `ClassMethods`) private.
- Added a public API contract spec to prevent accidental constant leakage.

### Added

- `Singulus::Singleton` for one managed instance per class.
- `Singulus::Multiton` for one managed instance per normalized identifier.
- `:standard`, `:strict`, and `:runtime` hardening modes.
- Include-time configuration with `Singulus::Singleton.with(...)` and `Singulus::Multiton.with(...)`.
- Two-step `singulus` DSL in addition to include-time `.with(...)` configuration.
- Multiton key normalization and defensive stabilization of common mutable keys.
- `:forever`, `:lru`, `:ttl`, `:bounded`, and `:weak` Multiton retention strategies.
- Explicit Multiton lifecycle operations: `instance?`, `instance_count`, `instance_keys`, `delete_instance`, and `clear_instances`.
- Thread-safe Singleton and Multiton initialization.
- Recursive Multiton initialization detection.
- Constructor, duplication, inheritance, mutation, and reflection guards in hardened modes.
- Runtime protection for common captured `Method` and `UnboundMethod` constructor/reflection paths.
- RSpec, RuboCop, SimpleCov, GitHub Actions CI, and RubyGems Trusted Publishing workflow.

### Security

- Guard `new` and `allocate` from the moment hardened Singulus modules are included.
- Prevent constructor bypass by changing constructor visibility.
- Reject constructor redefinition attempts in hardened modes.
- Protect common reflective constructor access paths.
- Protect captured `Method` and `UnboundMethod` paths in `:runtime` mode.

[Unreleased]: https://github.com/Rubcraft/singulus/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Rubcraft/singulus/releases/tag/v0.1.0
