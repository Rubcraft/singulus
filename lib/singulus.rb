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

# Configurable Singleton and keyed Multiton patterns for a Ruby process.
#
# Require `singulus`, then include {Singleton} or {Multiton} in a class.
# The default mode is `:strict`; `:standard` relaxes local guards and
# `:runtime` adds process-wide Method/UnboundMethod guards for managed classes.
# Runtime hardening is not a sandbox for code running in the same process.
#
# @see Singleton
# @see Multiton
# @see Error
module Singulus
  # Implementation details; not a supported public namespace.
  # @private
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
    # Returns the mutable process-wide defaults for subsequently installed classes.
    #
    # Use the returned object's `default_mode` reader and `default_mode=` writer;
    # its concrete class is private. The reader returns a Symbol. The writer accepts
    # `:standard`, `:strict`, `:runtime`, or their String forms, and raises
    # {Error} for invalid modes. Existing managed classes keep their mode.
    # Setting the writer directly does not install runtime guards until a runtime
    # class is installed; use {configure} to enable them immediately.
    #
    # @return [#default_mode, #default_mode=] shared configuration object
    # @example Read the default
    #   Singulus.configuration.default_mode # => :strict
    def configuration
      @configuration ||= Internal::Configuration.new
    end

    # Yields the shared configuration and enables runtime guards when requested.
    #
    # Configure during application boot, before defining managed classes or
    # capturing constructor references. Runtime patches are installed once and
    # remain installed for the life of the process. Exceptions from the block
    # propagate; changes already made to the configuration are not rolled back.
    #
    # @yield [config] changes defaults for future class installations
    # @yieldparam config [#default_mode, #default_mode=] mutable configuration
    # @yieldreturn [Object] ignored
    # @return [#default_mode, #default_mode=] shared configuration after the block
    # @raise [ArgumentError] if no block is given
    # @raise [Error] if the block assigns an unsupported default mode
    # @example Enable runtime hardening during boot
    #   Singulus.configure { |config| config.default_mode = :runtime }
    def configure
      raise ArgumentError, "a block is required" unless block_given?

      yield configuration
      Internal::RuntimeHardening.enable! if configuration.default_mode == :runtime
      configuration
    end

    # Replaces the shared configuration with a new object in `:strict` mode.
    #
    # Does not change existing classes, clear instances, or uninstall runtime
    # patches. Previously returned configuration objects are no longer shared.
    #
    # @return [#default_mode, #default_mode=] new configuration object
    def reset_configuration!
      @configuration = Internal::Configuration.new
    end
  end

  # Provides one lazily initialized, thread-safe instance per class and process.
  #
  # Include this module and call `.instance` on the including class. Construction
  # uses a zero-argument initializer. In strict/runtime modes constructors are
  # sealed after the first successful access, and duplication and inheritance
  # raise {Error}. Standard mode delegates singleton semantics to Ruby Singleton,
  # which rejects instance duplication with TypeError.
  #
  # Methods documented below as class methods are installed on the including
  # class, except {.with}, which is called on this module.
  #
  # @example Share one service
  #   class Settings
  #     include Singulus::Singleton
  #   end
  #   Settings.instance.equal?(Settings.instance) # => true
  module Singleton
    # @!method self.instance
    #   Returns the class's shared instance, constructing it once if needed.
    #
    #   Initialization is synchronized by Ruby Singleton. Initializer exceptions
    #   propagate and construction can be retried. Strict/runtime modes seal
    #   constructors after successful access. Recursive `.instance` calls from the
    #   initializer are unsupported by Ruby Singleton.
    #
    #   @return [Object] instance of the receiving class

    # @!method self.singulus(mode:)
    #   Changes this class's hardening mode.
    #
    #   Switching to runtime installs process-wide guards. Switching away does not
    #   uninstall them. A sealed Singleton cannot downgrade to standard mode.
    #
    #   @param mode [Symbol, String] :standard, :strict, or :runtime
    #   @return [Class] receiving class for chaining
    #   @raise [Error] for an invalid mode or a downgrade after constructor sealing

    # @!method self.singulus_mode
    #   Returns this class's current hardening mode.
    #   @return [Symbol] :standard, :strict, or :runtime

    # Inclusion helpers for the public mixin.
    class << self
      # Installs the pattern when Ruby evaluates `include`.
      # @private
      def included(base)
        Internal.install_singleton!(base)
      end

      # Builds an independent module with an include-time hardening mode.
      #
      # The default is captured when this method is called. Mode validation occurs
      # when the returned module is included in a class.
      #
      # @param mode [Symbol, String, nil] :standard, :strict, or :runtime;
      #   nil uses the configured default
      # @param options [Hash] keyword form of the mode
      # @option options [Symbol, String] :mode alternative to positional mode
      # @return [Module] module to include in the managed class
      # @raise [ArgumentError] if both mode forms or unknown options are supplied
      # @raise [Error] on inclusion if the resolved mode is unsupported
      # @example Select a mode for one class
      #   class Settings
      #     include Singulus::Singleton.with(mode: :runtime)
      #   end
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
