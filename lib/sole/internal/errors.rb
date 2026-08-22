# frozen_string_literal: true

module Sole
  class Error < StandardError; end

  module Internal
    class ConstructorAccessError < Sole::Error; end
    class DuplicationError < Sole::Error; end
    class InheritanceError < Sole::Error; end
    class InvalidModeError < Sole::Error; end
    class InvalidRetentionError < Sole::Error; end
    class ConfigurationLockedError < Sole::Error; end
    class RecursiveInitializationError < Sole::Error; end
  end
end
