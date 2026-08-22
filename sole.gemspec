# frozen_string_literal: true

require_relative "lib/sole/version"

Gem::Specification.new do |spec|
  spec.name = "sole"
  spec.version = Sole::VERSION
  spec.authors = ["Juan Furattini"]

  spec.summary = "Hardened Singleton and keyed Multiton patterns for Ruby"
  spec.description = <<~DESCRIPTION.strip
    Sole provides configurable local and runtime hardening for classic
    Singleton and keyed Multiton patterns, including reflection guards, constructor
    protection, mutation protection, inheritance restrictions, bounded retention
    strategies, and optional guards around Method and UnboundMethod.
  DESCRIPTION

  spec.homepage = "https://github.com/Rubcraft/sole"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["source_code_uri"] = "https://github.com/Rubcraft/sole"
  spec.metadata["changelog_uri"] = "https://github.com/Rubcraft/sole/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*", "README.md", "CHANGELOG.md", "LICENSE.txt"]
  end

  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler-audit", ">= 0.9", "< 1.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", ">= 3.13", "< 4.0"
  spec.add_development_dependency "rubocop", ">= 1.70", "< 2.0"
  spec.add_development_dependency "rubocop-performance", ">= 1.24", "< 2.0"
  spec.add_development_dependency "rubocop-rake", ">= 0.7", "< 1.0"
  spec.add_development_dependency "rubocop-rspec", ">= 3.0", "< 4.0"
  spec.add_development_dependency "simplecov", ">= 0.22", "< 1.0"
end
