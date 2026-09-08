# frozen_string_literal: true

module Singulus
  module Internal
    # Mutable defaults exposed through Singulus.configuration, not a public type.
    # @private
    class Configuration
      MODES = %i[standard strict runtime].freeze

      # Returns the mode applied to subsequently installed classes.
      # @return [Symbol] :standard, :strict, or :runtime
      attr_reader :default_mode

      # Initializes defaults in strict mode.
      def initialize
        self.default_mode = :strict
      end

      # Sets the default for subsequently installed classes.
      # @param mode [Symbol, String] standard, strict, or runtime
      # @return [Symbol] normalized mode
      # @raise [Singulus::Error] if the mode is unsupported
      def default_mode=(mode)
        mode = normalize_mode(mode)

        unless MODES.include?(mode)
          raise InvalidModeError,
                "invalid Singulus mode #{mode.inspect}; expected one of: #{MODES.join(', ')}"
        end

        @default_mode = mode
      end

      private

      def normalize_mode(mode)
        mode.to_sym
      rescue NoMethodError
        mode
      end
    end
  end
end
