# Sole

[![CI](https://github.com/Rubcraft/sole/actions/workflows/ci.yml/badge.svg)](https://github.com/Rubcraft/sole/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/sole.svg)](https://rubygems.org/gems/sole)


`Sole` adds configurable Ruby-level hardening around two instance-uniqueness patterns:

- `Sole::Singleton` — one instance per class and Ruby process.
- `Sole::Multiton` — one registered instance per class and normalized key.

It builds on Ruby's standard `Singleton` for the classic Singleton implementation and provides its own thread-safe keyed registry for Multiton.

Sole exposes one supported entry point:

```ruby
require "sole"
```

The supported root API is intentionally small:

- `Sole::Singleton`
- `Sole::Multiton`
- `Sole::Error` as the public base exception
- `Sole.configure`, `Sole.configuration`, and `Sole.reset_configuration!`
- `Sole::VERSION`

All implementation classes, guards, configuration types, and specialized errors live behind a private `Sole::Internal` namespace and are not public constants. No pre-release compatibility entry points are shipped.

## Security boundary

This gem is aggressive Ruby-level hardening, **not a sandbox**. Code executing in the same Ruby process can reopen core classes, use native extensions, replace guards, or otherwise modify the runtime. `:runtime` closes many common `Method`/`UnboundMethod` bypasses, but it cannot create a cryptographic or process-isolation boundary.

## Modes

```ruby
Sole.configure do |config|
  config.default_mode = :strict
end
```

Available modes:

- `:standard` — minimal policy. Classic Singleton delegates to Ruby `Singleton`; Multiton keeps constructors private but does not install local hardening policy.
- `:strict` — constructor reflection guards, mutation protection, duplication protection, inheritance restrictions, and constructor sealing for classic Singleton.
- `:runtime` — everything in `:strict`, plus process-wide `Method` and `UnboundMethod` guards that activate only for classes marked as runtime-hardened.

The default is `:strict`.

### Configure directly from `include`

`Singleton` and `Multiton` also expose `.with(...)`, which creates an independent configured inclusion module. It does not mutate the shared `Sole::Singleton` or `Sole::Multiton` module.

```ruby
class Configuration
  include Sole::Singleton.with(:strict)
end

class RuntimeConfiguration
  include Sole::Singleton.with(mode: :runtime)
end

class TenantConfiguration
  include Sole::Multiton.with(
    :runtime,
    retention: :lru,
    max_size: 5_000
  )
end
```

The existing two-step DSL remains supported and equivalent:

```ruby
include Sole::Singleton
sole mode: :strict
```

## Classic Singleton

```ruby
require "sole"

class Configuration
  include Sole::Singleton.with(:runtime)
end

Configuration.instance.equal?(Configuration.instance)
# => true
```

In hardened modes, direct constructor access is guarded from the moment the module is included, including attempts to change constructor visibility. Common reflection routes, duplication, constructor redefinition, and inheritance are rejected. After the first `instance`, classic Singleton also seals its constructor lookup path.

## Multiton: one instance per identifier

```ruby
class TenantConfiguration
  include Sole::Multiton.with(:strict)

  def initialize(tenant_id)
    @tenant_id = tenant_id
  end
end

one = TenantConfiguration.instance_for(10)
two = TenantConfiguration.instance_for(10)
other = TenantConfiguration.instance_for(20)

one.equal?(two)   # => true
one.equal?(other) # => false
```

`instance_for(identifier, *args, **kwargs)` passes the original identifier as the first initializer argument. Additional initializer arguments are used only when an instance for that normalized key does not already exist.

### Stable tenant keys

Prefer immutable identifiers such as integers, symbols, UUID strings, or normalized composite keys. Strings, arrays, and hashes returned as keys are defensively duplicated/frozen recursively where practical.

For domain objects, define a key normalizer:

```ruby
class TenantConfiguration
  include Sole::Multiton

  multiton_key { |tenant| tenant.id }

  def initialize(tenant)
    @tenant = tenant
  end
end
```

This avoids retaining an ActiveRecord object itself as the registry key.

## Multiton lifecycle

```ruby
TenantConfiguration.instance?(10)
TenantConfiguration.instance_count
TenantConfiguration.instance_keys
TenantConfiguration.delete_instance(10)
TenantConfiguration.clear_instances
```

`delete_instance` and `clear_instances` explicitly release registry ownership. If another part of the application still holds the old object, a later `instance_for` can create a new object for the same key. Therefore uniqueness is **registry/lifecycle scoped**, not a claim that no second live Ruby object can ever exist after explicit release or eviction.

## Retention strategies

The default is strict registry retention:

```ruby
class TenantConfiguration
  include Sole::Multiton
  multiton_retention :forever
end
```

Supported strategies:

### `:forever`

Keeps each registered instance until `delete_instance`/`clear_instances` or process exit. This is the strongest per-key identity guarantee supplied by Multiton.

### `:lru`

```ruby
multiton_retention :lru, max_size: 5_000
```

Bounds memory by evicting the least recently used registry entry. Once evicted, the same key can create a new instance later.

### `:ttl`

```ruby
multiton_retention :ttl, ttl: 300
```

Keeps an instance for a fixed TTL measured with `Process::CLOCK_MONOTONIC`. Expiration is based on creation time, not sliding access time. After expiration, the same key can create a new instance.

### `:bounded`

```ruby
multiton_retention :bounded, ttl: 300, max_size: 5_000
```

Combines TTL expiration with an LRU capacity bound. Entries are evicted when they expire or when the registry exceeds `max_size`. Use this instead of passing `max_size` to `:ttl` or `ttl` to `:lru`; those ambiguous configurations are rejected.

### `:weak`

```ruby
multiton_retention :weak
```

Stores weak references. Sole reuses the same object while it remains alive elsewhere, but the garbage collector may reclaim it when no strong references remain. A later `instance_for` can therefore create a new instance. `:weak` accepts neither `ttl` nor `max_size`.

| Strategy | `ttl` | `max_size` | Identity scope |
| --- | --- | --- | --- |
| `:forever` | no | no | until explicit release/process exit |
| `:lru` | no | required | while retained by capacity |
| `:ttl` | required | no | until expiration |
| `:bounded` | required | required | until expiration or capacity eviction |
| `:weak` | no | no | while the object remains strongly referenced |

`multiton_key` and retention configuration are locked while the registry contains instances. Call `clear_instances` before changing them deliberately.

## Runtime hardening

Runtime mode additionally guards common bypasses involving:

- `Method#call`
- `Method#[]`
- `Method#to_proc`
- `Method#>>` / `Method#<<`
- `UnboundMethod#bind`
- `UnboundMethod#bind_call`
- captured reflection gateways such as `Object#method` and `BasicObject#__send__`

The patches are installed process-wide once required, but their rejection logic only activates for classes marked `:runtime`.

Enable runtime mode as early as possible during boot:

```ruby
Sole.configure do |config|
  config.default_mode = :runtime
end
```

For Rails, place this in an early initializer before code that might capture constructor references.

A `Proc` created from a constructor `Method` *before* Sole runtime hardening is enabled cannot be retroactively identified as constructor-derived. Enable `:runtime` during boot, before untrusted or extension code can capture such references.

## Development

```bash
bundle install
bundle exec rubocop --parallel
bundle exec rspec
bundle exec bundler-audit check --update
bundle exec rake build
```

SimpleCov enforces line and branch coverage, while CI tests supported Ruby versions independently from RuboCop.

## Releasing

Repository initialization, version-control operations, and release-tag creation are managed by the Rubcraft Toolkit. Sole itself does not prescribe or duplicate those commands.

The repository keeps only the CI/publish boundary: `.github/workflows/release.yml` reacts to a version tag produced by the Toolkit, verifies that it matches `Sole::VERSION`, runs quality checks, builds the gem, and publishes through RubyGems Trusted Publishing (OIDC). Configure a GitHub environment named `release` and the matching RubyGems Trusted Publisher before the first release.
