# frozen_string_literal: true

module Sole
  module Internal
    class Configuration
      MODES = %i[standard strict runtime].freeze

      attr_reader :default_mode

      def initialize
        self.default_mode = :strict
      end

      def default_mode=(mode)
        mode = normalize_mode(mode)

        unless MODES.include?(mode)
          raise InvalidModeError,
                "invalid Sole mode #{mode.inspect}; expected one of: #{MODES.join(', ')}"
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
