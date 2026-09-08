# frozen_string_literal: true

module Singulus
  # Provides a synchronized registry of instances indexed by normalized keys.
  #
  # Include this module and call `.instance_for` on the including class.
  # Uniqueness lasts only while an entry is retained: deletion, expiration,
  # eviction, or weak-reference collection allows a new object for the same key,
  # even if application code still holds a previously released instance.
  # Strict/runtime modes reject duplication and subclassing with {Error}.
  # Standard-mode subclasses start with independent, default-configured registries.
  #
  # Methods documented below as class methods are installed on the including
  # class, except {.with}, which is called on this module. Configure classes
  # at boot before using them concurrently.
  #
  # @example Reuse a tenant-specific service
  #   class TenantService
  #     include Singulus::Multiton
  #     def initialize(tenant_id)
  #       @tenant_id = tenant_id
  #     end
  #   end
  #   TenantService.instance_for(10).equal?(TenantService.instance_for(10)) # => true
  module Multiton
    # @!method self.instance_for(identifier, *args, **kwargs, &block)
    #   Returns the retained instance for a key, or constructs and stores one.
    #
    #   The normalizer determines the registry key, but the original identifier,
    #   additional arguments, keywords, and block are forwarded to `initialize` only
    #   on a cache miss. A hit ignores the additional initialization inputs.
    #   Construction and registry access are synchronized per class. Expired and dead
    #   weak entries are purged first; a hit refreshes LRU order, but never the TTL.
    #   Initializer and key-normalizer exceptions propagate. Failed initialization
    #   is not cached, so a later call may retry.
    #
    #   @param identifier [Object] original identifier passed first to initialize
    #   @param args [Array<Object>] remaining positional initializer arguments
    #   @param kwargs [Hash] initializer keyword arguments
    #   @param block [Proc, nil] block forwarded to initialize on a miss
    #   @return [Object] instance of the receiving class
    #   @raise [Error] if initialization recursively requests the same normalized key
    #   @see multiton_key
    #   @see multiton_retention

    # @!method self.instance?(identifier)
    #   Checks whether a live entry exists without constructing an instance.
    #
    #   Purges expired/dead entries and does not refresh LRU order or TTL.
    #   Key-normalizer exceptions propagate.
    #
    #   @param identifier [Object] identifier to normalize and look up
    #   @return [Boolean] whether the normalized key is registered

    # @!method self.delete_instance(identifier)
    #   Removes registry ownership of a live entry and returns its instance.
    #
    #   Purges expired/dead entries first. Existing external references stay valid;
    #   a later lookup can construct another instance. Normalizer exceptions propagate.
    #
    #   @param identifier [Object] identifier to normalize and remove
    #   @return [Object, nil] removed instance, or nil if no live entry exists

    # @!method self.clear_instances
    #   Releases all registry entries after purging expired/dead entries.
    #
    #   External references remain valid. The empty registry allows changes to its
    #   key normalizer and retention policy.
    #
    #   @return [Integer] number of live entries removed

    # @!method self.instance_count
    #   Counts registered entries after purging expired/dead entries.
    #   @return [Integer] current registry size

    # @!method self.instance_keys
    #   Returns a frozen snapshot of keys after purging expired/dead entries.
    #
    #   Keys are normalized keys, not necessarily the original identifiers. Strings,
    #   arrays, and hashes are recursively copied/frozen when registered; other key
    #   objects are not copied. This operation does not refresh LRU order or TTL.
    #
    #   @return [Array<Object>] frozen array of currently registered keys

    # @!method self.singulus(mode: nil, retention: nil, ttl: nil, max_size: nil)
    #   Updates the class mode and/or retention policy, returning the class.
    #
    #   Mode is applied first; a subsequent retention error does not roll it back.
    #   TTL/capacity settings are ignored unless retention is provided.
    #
    #   @param mode [Symbol, String, nil] hardening mode; nil leaves it unchanged
    #   @param retention [Symbol, String, nil] strategy; nil leaves it unchanged
    #   @param ttl [Numeric, nil] positive lifetime in seconds for ttl/bounded
    #   @param max_size [Integer, nil] positive capacity for lru/bounded
    #   @return [Class] receiving class
    #   @raise [Error] for invalid settings or retention changes on a nonempty registry
    #   @see multiton_retention

    # @!method self.singulus_mode
    #   Returns this class's current hardening mode.
    #   @return [Symbol] :standard, :strict, or :runtime

    # @!method self.multiton_key(&block)
    #   Reads or replaces the key normalizer used by identifier-based operations.
    #
    #   The block receives the original identifier. Its result becomes the registry
    #   key, with strings, arrays, and hashes recursively copied/frozen. Other objects
    #   must keep stable `hash` and `eql?` behavior while registered. No block means
    #   read the current normalizer; nil means identifiers are used directly.
    #   Clear the registry before changing normalization. Block exceptions propagate
    #   from subsequent identifier-based operations.
    #
    #   @param block [Proc, nil] normalizer to install, or nil to read
    #   @yield [identifier] computes a registry key
    #   @yieldparam identifier [Object] original identifier
    #   @yieldreturn [Object] stable key
    #   @return [Class, Proc, nil] class when setting; current normalizer when reading
    #   @raise [Error] if setting a normalizer while live entries remain
    #   @example Normalize case before creating instances
    #     TenantService.multiton_key { |id| id.to_s.downcase }

    # @!method self.multiton_retention(strategy = nil, ttl: nil, max_size: nil)
    #   Reads or replaces the registry retention policy (initially `:forever`).
    #
    #   `forever` holds entries until explicit release; `weak` holds weak references.
    #   Neither accepts TTL or capacity. `lru` requires only max_size and evicts the
    #   least recently accessed entry. `ttl` requires only ttl and expires entries
    #   from their creation time using the monotonic clock. `bounded` requires both.
    #   Expiration is lazy, checked during registry operations, not by a background
    #   worker. TTL never slides on access. All policies can allow new instances
    #   after an entry is released. Settings may change only on an empty registry.
    #
    #   @param strategy [Symbol, String, nil] forever, weak, lru, ttl, or bounded;
    #     nil reads the current strategy and ignores other arguments
    #   @param ttl [Numeric, nil] positive seconds (converted with to_f)
    #   @param max_size [Integer, nil] positive capacity (converted with to_i)
    #   @return [Class, Symbol] class when setting; strategy when reading
    #   @raise [Error] for an unknown strategy, incompatible/missing/nonpositive
    #     options, or a nonempty registry
    #   @example Combine time and capacity bounds
    #     TenantService.clear_instances
    #     TenantService.multiton_retention(:bounded, ttl: 300, max_size: 100)

    # Supported internal retention names.
    # @private
    RETENTIONS = %i[forever lru ttl bounded weak].freeze
    private_constant :RETENTIONS

    # Internal registry entry, optionally holding a weak reference.
    # @private
    Entry = Struct.new(:value, :expires_at, keyword_init: true) do
      def instance
        value.is_a?(WeakRef) ? value.__getobj__ : value
      rescue WeakRef::RefError
        nil
      end

      def alive?
        !instance.nil?
      end
    end
    private_constant :Entry

    class << self
      # Installs the pattern when Ruby evaluates `include`.
      # @private
      def included(base)
        install(base)
      end

      # Builds an independent module with mode and optional retention settings.
      #
      # Defaults are captured now; mode and retention validation happens on inclusion.
      # `ttl` and `max_size` are applied only when `retention` is supplied.
      # See {.multiton_retention} for supported combinations.
      #
      # @param mode [Symbol, String, nil] :standard, :strict, or :runtime;
      #   nil uses the configured default
      # @param options [Hash] mode and registry settings
      # @option options [Symbol, String] :mode alternative to positional mode
      # @option options [Symbol, String] :retention registry retention strategy
      # @option options [Numeric] :ttl positive lifetime in seconds
      # @option options [Integer] :max_size positive registry capacity
      # @return [Module] configured module to include in a class
      # @raise [ArgumentError] if both mode forms or unknown options are supplied
      # @raise [Error] on inclusion for invalid mode or retention settings
      # @example Limit registry capacity
      #   class TenantService
      #     include Singulus::Multiton.with(:strict, retention: :lru, max_size: 100)
      #     def initialize(tenant_id)
      #       @tenant_id = tenant_id
      #     end
      #   end
      def with(mode = nil, **options)
        resolved_mode = options.delete(:mode)

        raise ArgumentError, "mode must be provided either positionally or as mode:, not both" if mode && resolved_mode

        resolved_mode ||= mode || Singulus.configuration.default_mode
        retention = options.delete(:retention)
        ttl = options.delete(:ttl)
        max_size = options.delete(:max_size)

        raise ArgumentError, "unknown Multiton options: #{options.keys.map(&:inspect).join(', ')}" unless options.empty?

        Module.new do
          define_singleton_method(:included) do |base|
            Multiton.install(base, mode: resolved_mode)
            base.singulus(retention: retention, ttl: ttl, max_size: max_size) if retention
          end
        end
      end

      # Installs guards and a fresh registry on a class.
      # @private
      def install(base, mode: Singulus.configuration.default_mode)
        Internal.initialize_managed_class!(base, kind: :multiton, mode: mode)

        base.include Internal::InstanceGuard
        base.private_class_method :new, :allocate
        base.singleton_class.prepend Internal::ReflectionGuard
        base.singleton_class.prepend Internal::MutationGuard
        base.singleton_class.prepend Internal::ConstructorGuard
        base.extend ClassMethods

        initialize_registry_state(base)
        Internal::RuntimeHardening.enable! if Internal.runtime_hardened?(base)
        base
      end

      private

      def initialize_registry_state(base)
        base.instance_variable_set(:@__singulus_multiton_mutex__, Monitor.new)
        base.instance_variable_set(:@__singulus_multiton_instances__, {})
        base.instance_variable_set(:@__singulus_multiton_key_normalizer__, nil)
        base.instance_variable_set(:@__singulus_multiton_retention__, :forever)
        base.instance_variable_set(:@__singulus_multiton_ttl__, nil)
        base.instance_variable_set(:@__singulus_multiton_max_size__, nil)
        base.instance_variable_set(:@__singulus_multiton_initializing_keys__, {})
      end
    end

    # Implementation of methods installed on each Multiton class.
    # @private
    module ClassMethods
      # See {Singulus::Multiton.instance_for} for the public contract.
      def instance_for(identifier, ...)
        key = singulus_multiton_key_for(identifier)

        singulus_multiton_mutex.synchronize do
          singulus_multiton_purge_expired!

          if (entry = singulus_multiton_instances[key])
            if (instance = entry.instance)
              singulus_multiton_touch_lru!(key, entry)
              return instance
            end

            singulus_multiton_instances.delete(key)
          end

          singulus_multiton_reject_recursive_initialization!(key)
          singulus_multiton_initializing_keys[key] = true

          begin
            instance = Internal.with_constructor_access(self) do
              new(identifier, ...)
            end
            singulus_multiton_store!(key, instance)
            instance
          ensure
            singulus_multiton_initializing_keys.delete(key)
          end
        end
      end

      # See {Singulus::Multiton.instance?} for the public contract.
      def instance?(identifier)
        key = singulus_multiton_key_for(identifier)

        singulus_multiton_mutex.synchronize do
          singulus_multiton_purge_expired!
          singulus_multiton_instances.key?(key)
        end
      end

      # See {Singulus::Multiton.delete_instance} for the public contract.
      def delete_instance(identifier)
        key = singulus_multiton_key_for(identifier)

        singulus_multiton_mutex.synchronize do
          singulus_multiton_purge_expired!
          singulus_multiton_instances.delete(key)&.instance
        end
      end

      # See {Singulus::Multiton.clear_instances} for the public contract.
      def clear_instances
        singulus_multiton_mutex.synchronize do
          singulus_multiton_purge_expired!
          count = singulus_multiton_instances.length
          singulus_multiton_instances.clear
          count
        end
      end

      # See {Singulus::Multiton.instance_count} for the public contract.
      def instance_count
        singulus_multiton_mutex.synchronize do
          singulus_multiton_purge_expired!
          singulus_multiton_instances.length
        end
      end

      # See {Singulus::Multiton.instance_keys} for the public contract.
      def instance_keys
        singulus_multiton_mutex.synchronize do
          singulus_multiton_purge_expired!
          singulus_multiton_instances.keys.dup.freeze
        end
      end

      # See {Singulus::Multiton.singulus} for the public contract.
      def singulus(mode: nil, retention: nil, ttl: nil, max_size: nil)
        Internal.set_mode!(self, mode) if mode
        multiton_retention(retention, ttl: ttl, max_size: max_size) if retention
        self
      end

      # See {Singulus::Multiton.singulus_mode} for the public contract.
      def singulus_mode
        Internal.mode_for(self)
      end

      # See {Singulus::Multiton.multiton_key} for the public contract.
      def multiton_key(&block)
        return @__singulus_multiton_key_normalizer__ unless block

        singulus_multiton_assert_registry_empty!("key normalizer")
        @__singulus_multiton_key_normalizer__ = block
        self
      end

      # See {Singulus::Multiton.multiton_retention} for the public contract.
      def multiton_retention(strategy = nil, ttl: nil, max_size: nil)
        return @__singulus_multiton_retention__ unless strategy

        strategy = Internal.normalize_method_name(strategy)
        unless RETENTIONS.include?(strategy)
          raise Internal::InvalidRetentionError,
                "invalid Multiton retention #{strategy.inspect}; expected one of: #{RETENTIONS.join(', ')}"
        end

        singulus_multiton_validate_retention_options!(strategy, ttl: ttl, max_size: max_size)
        singulus_multiton_assert_registry_empty!("retention")

        @__singulus_multiton_retention__ = strategy
        @__singulus_multiton_ttl__ = ttl&.to_f
        @__singulus_multiton_max_size__ = max_size&.to_i
        self
      end

      private

      def inherited(subclass)
        if Internal.locally_hardened?(self)
          raise Internal::InheritanceError,
                "#{self} is a Multiton in #{singulus_mode.inspect} mode and cannot be subclassed"
        end

        super
        Multiton.install(subclass, mode: singulus_mode)
      end

      def singulus_multiton_instances
        @__singulus_multiton_instances__ ||= {}
      end

      def singulus_multiton_mutex
        @__singulus_multiton_mutex__ ||= Monitor.new
      end

      def singulus_multiton_initializing_keys
        @__singulus_multiton_initializing_keys__ ||= {}
      end

      def singulus_multiton_key_for(identifier)
        normalizer = @__singulus_multiton_key_normalizer__
        key = normalizer ? normalizer.call(identifier) : identifier
        singulus_multiton_stabilize_key(key)
      end

      def singulus_multiton_stabilize_key(key)
        case key
        when String
          key.dup.freeze
        when Array
          key.map { |item| singulus_multiton_stabilize_key(item) }.freeze
        when Hash
          key.each_with_object({}) do |(hash_key, value), stabilized|
            stabilized[singulus_multiton_stabilize_key(hash_key)] = singulus_multiton_stabilize_key(value)
          end.freeze
        else
          key
        end
      end

      def singulus_multiton_store!(key, instance)
        retention = @__singulus_multiton_retention__
        ttl_retention = %i[ttl bounded].include?(retention)
        expires_at = singulus_multiton_monotonic_time + @__singulus_multiton_ttl__ if ttl_retention
        value = retention == :weak ? WeakRef.new(instance) : instance

        singulus_multiton_instances[key] = Entry.new(value: value, expires_at: expires_at)
        singulus_multiton_evict_lru! if %i[lru bounded].include?(retention)
      end

      def singulus_multiton_touch_lru!(key, entry)
        return unless %i[lru bounded].include?(@__singulus_multiton_retention__)

        singulus_multiton_instances.delete(key)
        singulus_multiton_instances[key] = entry
      end

      def singulus_multiton_evict_lru!
        max_size = @__singulus_multiton_max_size__
        singulus_multiton_instances.shift while singulus_multiton_instances.length > max_size
      end

      def singulus_multiton_purge_expired!
        retention = @__singulus_multiton_retention__

        if %i[ttl bounded].include?(retention)
          now = singulus_multiton_monotonic_time
          singulus_multiton_instances.delete_if { |_key, entry| entry.expires_at <= now }
        elsif retention == :weak
          singulus_multiton_instances.delete_if { |_key, entry| !entry.alive? }
        end
      end

      def singulus_multiton_monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def singulus_multiton_validate_retention_options!(strategy, ttl:, max_size:)
        case strategy
        when :forever, :weak
          return unless ttl || max_size

          raise Internal::InvalidRetentionError,
                "#{strategy.inspect} retention does not accept ttl: or max_size:"
        when :ttl
          if !ttl || ttl.to_f <= 0
            raise Internal::InvalidRetentionError,
                  ":ttl retention requires ttl: greater than zero"
          end
          return unless max_size

          raise Internal::InvalidRetentionError,
                "max_size: is not valid for :ttl retention; use retention: :bounded to combine ttl and max_size"
        when :lru
          if !max_size || max_size.to_i <= 0
            raise Internal::InvalidRetentionError, ":lru retention requires max_size: greater than zero"
          end
          return unless ttl

          raise Internal::InvalidRetentionError,
                "ttl: is not valid for :lru retention; use retention: :bounded to combine ttl and max_size"
        when :bounded
          if !ttl || ttl.to_f <= 0
            raise Internal::InvalidRetentionError,
                  ":bounded retention requires ttl: greater than zero"
          end
          return if max_size&.to_i&.positive?

          raise Internal::InvalidRetentionError, ":bounded retention requires max_size: greater than zero"
        end
      end

      def singulus_multiton_reject_recursive_initialization!(key)
        return unless singulus_multiton_initializing_keys.key?(key)

        raise Internal::RecursiveInitializationError,
              "recursive Multiton initialization detected for key #{key.inspect} on #{self}"
      end

      def singulus_multiton_assert_registry_empty!(setting)
        return if instance_count.zero?

        raise Internal::ConfigurationLockedError,
              "cannot change Multiton #{setting} after instances have been created; clear_instances first"
      end
    end

    private_constant :ClassMethods
  end
end
