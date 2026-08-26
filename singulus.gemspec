# frozen_string_literal: true

require_relative "lib/singulus/version"

Gem::Specification.new do |spec|
  spec.name = "singulus"
  spec.version = Singulus::VERSION
  spec.authors = ["Juan Furattini"]

  spec.summary = "Hardened Singleton and keyed Multiton patterns for Ruby"
  spec.description = <<~DESCRIPTION.strip
    Singulus provides configurable local and runtime hardening for classic
    Singleton and keyed Multiton patterns, including reflection guards, constructor
    protection, mutation protection, inheritance restrictions, bounded retention
    strategies, and optional guards around Method and UnboundMethod.
  DESCRIPTION

  spec.homepage = "https://github.com/Rubcraft/singulus"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["source_code_uri"] = "https://github.com/Rubcraft/singulus"
  spec.metadata["changelog_uri"] = "https://github.com/Rubcraft/singulus/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*", "README.md", "CHANGELOG.md", "LICENSE.txt"]
  end

  spec.require_paths = ["lib"]
end
