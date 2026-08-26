# frozen_string_literal: true

require "singleton"
require "monitor"
require "weakref"

require_relative "singulus/version"
require_relative "singulus/internal/errors"
require_relative "singulus/internal/configuration"
require_relative "singulus/internal/instance_guard"
require_relative "singulus/internal/constructor_guard"
require_relative "singulus/internal/reflection_guard"
require_relative "singulus/internal/mutation_guard"
require_relative "singulus/internal/singleton_class_methods"
require_relative "singulus/internal/runtime_hardening"
require_relative "singulus/multiton"

module Singulus
  module Internal
    CONSTRUCTORS = %i[new allocate].freeze

    MARKER_IVAR = :@__singulus_managed_class__
    KIND_IVAR = :@__singulus_kind__
    MODE_IVAR = :@__singulus_mode__

    class << self
      def install_singleton!(base, mode: Singulus.configuration.default_mode)
        base.include ::Singleton
        base.include InstanceGuard

        initialize_managed_class!(base, kind: :singleton, mode: mode)
        base.instance_variable_set(:@__singulus_seal_mutex__, Thread::Mutex.new)
        base.instance_variable_set(:@__singulus_sealed__, false)

        base.singleton_class.prepend ReflectionGuard
        base.singleton_class.prepend MutationGuard
        base.singleton_class.prepend ConstructorGuard
        base.extend SingletonClassMethods

        RuntimeHardening.enable! if runtime_hardened?(base)
        base
      end

      def initialize_managed_class!(base, kind:, mode:)
        base.instance_variable_set(MARKER_IVAR, true)
        base.instance_variable_set(KIND_IVAR, kind)
        base.instance_variable_set(MODE_IVAR, normalize_mode!(mode))
        base
      end

      def managed_class?(object)
        object.is_a?(Class) && object.instance_variable_get(MARKER_IVAR) == true
      end

      alias singulus_class? managed_class?

      def kind_for(klass)
        return unless managed_class?(klass)

        klass.instance_variable_get(KIND_IVAR)
      end

      def mode_for(klass)
        return unless managed_class?(klass)

        klass.instance_variable_get(MODE_IVAR)
      end

      def set_mode!(klass, mode)
        raise ArgumentError, "#{klass} is not managed by Singulus" unless managed_class?(klass)

        normalized_mode = normalize_mode!(mode)
        current_mode = mode_for(klass)

        if kind_for(klass) == :singleton && current_mode != :standard && normalized_mode == :standard &&
           klass.instance_variable_get(:@__singulus_sealed__)
          raise InvalidModeError,
                "cannot downgrade #{klass} to :standard after its constructors have been sealed"
        end

        klass.instance_variable_set(MODE_IVAR, normalized_mode)
        RuntimeHardening.enable! if normalized_mode == :runtime
        normalized_mode
      end

      def locally_hardened?(klass)
        %i[strict runtime].include?(mode_for(klass))
      end

      def runtime_hardened?(klass)
        mode_for(klass) == :runtime
      end

      def sealed_singleton?(klass)
        kind_for(klass) == :singleton && klass.instance_variable_get(:@__singulus_sealed__) == true
      end

      def constructor_name?(method_name)
        CONSTRUCTORS.include?(normalize_method_name(method_name))
      end

      def normalize_method_name(method_name)
        method_name.to_sym
      rescue NoMethodError
        method_name
      end

      def constructor_access_allowed?(klass)
        permissions = Thread.current[:__singulus_constructor_permissions__]
        permissions && permissions[klass].to_i.positive?
      end

      def with_constructor_access(klass)
        permissions = (Thread.current[:__singulus_constructor_permissions__] ||= {})
        permissions[klass] = permissions[klass].to_i + 1
        yield
      ensure
        if permissions
          permissions[klass] = permissions[klass].to_i - 1
          permissions.delete(klass) unless permissions[klass].to_i.positive?
          Thread.current[:__singulus_constructor_permissions__] = nil if permissions.empty?
        end
      end

      private

      def normalize_mode!(mode)
        normalized_mode = normalize_method_name(mode)
        return normalized_mode if Configuration::MODES.include?(normalized_mode)

        raise InvalidModeError,
              "invalid Singulus mode #{mode.inspect}; expected one of: #{Configuration::MODES.join(', ')}"
      end
    end
  end

  private_constant :Internal

  class << self
    def configuration
      @configuration ||= Internal::Configuration.new
    end

    def configure
      raise ArgumentError, "a block is required" unless block_given?

      yield configuration
      Internal::RuntimeHardening.enable! if configuration.default_mode == :runtime
      configuration
    end

    def reset_configuration!
      @configuration = Internal::Configuration.new
    end
  end

  module Singleton
    class << self
      def included(base)
        Internal.install_singleton!(base)
      end

      def with(mode = nil, **options)
        resolved_mode = options.delete(:mode)

        raise ArgumentError, "mode must be provided either positionally or as mode:, not both" if mode && resolved_mode

        unless options.empty?
          raise ArgumentError, "unknown Singleton options: #{options.keys.map(&:inspect).join(', ')}"
        end

        resolved_mode ||= mode || Singulus.configuration.default_mode

        Module.new do
          define_singleton_method(:included) do |base|
            Internal.install_singleton!(base, mode: resolved_mode)
          end
        end
      end
    end
  end
end
