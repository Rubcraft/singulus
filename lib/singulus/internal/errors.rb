# frozen_string_literal: true

module Singulus
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
