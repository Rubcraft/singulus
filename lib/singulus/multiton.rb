# frozen_string_literal: true

module Singulus
  module Multiton
    RETENTIONS = %i[forever lru ttl bounded weak].freeze
    private_constant :RETENTIONS

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
      def included(base)
        install(base)
      end

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

    module ClassMethods
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

      def instance?(identifier)
        key = singulus_multiton_key_for(identifier)

        singulus_multiton_mutex.synchronize do
          singulus_multiton_purge_expired!
          singulus_multiton_instances.key?(key)
        end
      end

      def delete_instance(identifier)
        key = singulus_multiton_key_for(identifier)

        singulus_multiton_mutex.synchronize do
          singulus_multiton_purge_expired!
          singulus_multiton_instances.delete(key)&.instance
        end
      end

      def clear_instances
        singulus_multiton_mutex.synchronize do
          singulus_multiton_purge_expired!
          count = singulus_multiton_instances.length
          singulus_multiton_instances.clear
          count
        end
      end

      def instance_count
        singulus_multiton_mutex.synchronize do
          singulus_multiton_purge_expired!
          singulus_multiton_instances.length
        end
      end

      def instance_keys
        singulus_multiton_mutex.synchronize do
          singulus_multiton_purge_expired!
          singulus_multiton_instances.keys.dup.freeze
        end
      end

      def singulus(mode: nil, retention: nil, ttl: nil, max_size: nil)
        Internal.set_mode!(self, mode) if mode
        multiton_retention(retention, ttl: ttl, max_size: max_size) if retention
        self
      end

      def singulus_mode
        Internal.mode_for(self)
      end

      def multiton_key(&block)
        return @__singulus_multiton_key_normalizer__ unless block

        singulus_multiton_assert_registry_empty!("key normalizer")
        @__singulus_multiton_key_normalizer__ = block
        self
      end

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
