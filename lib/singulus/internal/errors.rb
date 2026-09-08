# frozen_string_literal: true

module Singulus
  # Public base exception for Singulus policy and configuration failures.
  #
  # Rescue this class for invalid modes/retention, locked registry settings,
  # recursive Multiton initialization, and hardening violations. Specialized
  # subclasses are private implementation details. Ruby and application errors
  # (such as ArgumentError or initializer failures) are not wrapped.
  #
  # @example Handle a rejected configuration
  #   begin
  #     Singulus.configure { |config| config.default_mode = :unknown }
  #   rescue Singulus::Error => error
  #     warn error.message
  #   end
  class Error < StandardError; end

  module Internal
    class ConstructorAccessError < Singulus::Error; end
    class DuplicationError < Singulus::Error; end
    class InheritanceError < Singulus::Error; end
    class InvalidModeError < Singulus::Error; end
    class InvalidRetentionError < Singulus::Error; end
    class ConfigurationLockedError < Singulus::Error; end
    class RecursiveInitializationError < Singulus::Error; end
  end
end
