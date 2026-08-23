# frozen_string_literal: true

module Sole
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

        resolved_mode ||= mode || Sole.configuration.default_mode
        retention = options.delete(:retention)
        ttl = options.delete(:ttl)
        max_size = options.delete(:max_size)

        raise ArgumentError, "unknown Multiton options: #{options.keys.map(&:inspect).join(', ')}" unless options.empty?

        Module.new do
          define_singleton_method(:included) do |base|
            Multiton.install(base, mode: resolved_mode)
            base.sole(retention: retention, ttl: ttl, max_size: max_size) if retention
          end
        end
      end

      def install(base, mode: Sole.configuration.default_mode)
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
        base.instance_variable_set(:@__sole_multiton_mutex__, Monitor.new)
        base.instance_variable_set(:@__sole_multiton_instances__, {})
        base.instance_variable_set(:@__sole_multiton_key_normalizer__, nil)
        base.instance_variable_set(:@__sole_multiton_retention__, :forever)
        base.instance_variable_set(:@__sole_multiton_ttl__, nil)
        base.instance_variable_set(:@__sole_multiton_max_size__, nil)
        base.instance_variable_set(:@__sole_multiton_initializing_keys__, {})
      end
    end

    module ClassMethods
      def instance_for(identifier, ...)
        key = sole_multiton_key_for(identifier)

        sole_multiton_mutex.synchronize do
          sole_multiton_purge_expired!

          if (entry = sole_multiton_instances[key])
            if (instance = entry.instance)
              sole_multiton_touch_lru!(key, entry)
              return instance
            end

            sole_multiton_instances.delete(key)
          end

          sole_multiton_reject_recursive_initialization!(key)
          sole_multiton_initializing_keys[key] = true

          begin
            instance = Internal.with_constructor_access(self) do
              new(identifier, ...)
            end
            sole_multiton_store!(key, instance)
            instance
          ensure
            sole_multiton_initializing_keys.delete(key)
          end
        end
      end

      def instance?(identifier)
        key = sole_multiton_key_for(identifier)

        sole_multiton_mutex.synchronize do
          sole_multiton_purge_expired!
          sole_multiton_instances.key?(key)
        end
      end

      def delete_instance(identifier)
        key = sole_multiton_key_for(identifier)

        sole_multiton_mutex.synchronize do
          sole_multiton_purge_expired!
          sole_multiton_instances.delete(key)&.instance
        end
      end

      def clear_instances
        sole_multiton_mutex.synchronize do
          sole_multiton_purge_expired!
          count = sole_multiton_instances.length
          sole_multiton_instances.clear
          count
        end
      end

      def instance_count
        sole_multiton_mutex.synchronize do
          sole_multiton_purge_expired!
          sole_multiton_instances.length
        end
      end

      def instance_keys
        sole_multiton_mutex.synchronize do
          sole_multiton_purge_expired!
          sole_multiton_instances.keys.dup.freeze
        end
      end

      def sole(mode: nil, retention: nil, ttl: nil, max_size: nil)
        Internal.set_mode!(self, mode) if mode
        multiton_retention(retention, ttl: ttl, max_size: max_size) if retention
        self
      end

      def sole_mode
        Internal.mode_for(self)
      end

      def multiton_key(&block)
        return @__sole_multiton_key_normalizer__ unless block

        sole_multiton_assert_registry_empty!("key normalizer")
        @__sole_multiton_key_normalizer__ = block
        self
      end

      def multiton_retention(strategy = nil, ttl: nil, max_size: nil)
        return @__sole_multiton_retention__ unless strategy

        strategy = Internal.normalize_method_name(strategy)
        unless RETENTIONS.include?(strategy)
          raise Internal::InvalidRetentionError,
                "invalid Multiton retention #{strategy.inspect}; expected one of: #{RETENTIONS.join(', ')}"
        end

        sole_multiton_validate_retention_options!(strategy, ttl: ttl, max_size: max_size)
        sole_multiton_assert_registry_empty!("retention")

        @__sole_multiton_retention__ = strategy
        @__sole_multiton_ttl__ = ttl&.to_f
        @__sole_multiton_max_size__ = max_size&.to_i
        self
      end

      private

      def inherited(subclass)
        if Internal.locally_hardened?(self)
          raise Internal::InheritanceError,
                "#{self} is a Multiton in #{sole_mode.inspect} mode and cannot be subclassed"
        end

        super
        Multiton.install(subclass, mode: sole_mode)
      end

      def sole_multiton_instances
        @__sole_multiton_instances__ ||= {}
      end

      def sole_multiton_mutex
        @__sole_multiton_mutex__ ||= Monitor.new
      end

      def sole_multiton_initializing_keys
        @__sole_multiton_initializing_keys__ ||= {}
      end

      def sole_multiton_key_for(identifier)
        normalizer = @__sole_multiton_key_normalizer__
        key = normalizer ? normalizer.call(identifier) : identifier
        sole_multiton_stabilize_key(key)
      end

      def sole_multiton_stabilize_key(key)
        case key
        when String
          key.dup.freeze
        when Array
          key.map { |item| sole_multiton_stabilize_key(item) }.freeze
        when Hash
          key.each_with_object({}) do |(hash_key, value), stabilized|
            stabilized[sole_multiton_stabilize_key(hash_key)] = sole_multiton_stabilize_key(value)
          end.freeze
        else
          key
        end
      end

      def sole_multiton_store!(key, instance)
        retention = @__sole_multiton_retention__
        expires_at = sole_multiton_monotonic_time + @__sole_multiton_ttl__ if %i[ttl bounded].include?(retention)
        value = retention == :weak ? WeakRef.new(instance) : instance

        sole_multiton_instances[key] = Entry.new(value: value, expires_at: expires_at)
        sole_multiton_evict_lru! if %i[lru bounded].include?(retention)
      end

      def sole_multiton_touch_lru!(key, entry)
        return unless %i[lru bounded].include?(@__sole_multiton_retention__)

        sole_multiton_instances.delete(key)
        sole_multiton_instances[key] = entry
      end

      def sole_multiton_evict_lru!
        max_size = @__sole_multiton_max_size__
        sole_multiton_instances.shift while sole_multiton_instances.length > max_size
      end

      def sole_multiton_purge_expired!
        retention = @__sole_multiton_retention__

        if %i[ttl bounded].include?(retention)
          now = sole_multiton_monotonic_time
          sole_multiton_instances.delete_if { |_key, entry| entry.expires_at <= now }
        elsif retention == :weak
          sole_multiton_instances.delete_if { |_key, entry| !entry.alive? }
        end
      end

      def sole_multiton_monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def sole_multiton_validate_retention_options!(strategy, ttl:, max_size:)
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

      def sole_multiton_reject_recursive_initialization!(key)
        return unless sole_multiton_initializing_keys.key?(key)

        raise Internal::RecursiveInitializationError,
              "recursive Multiton initialization detected for key #{key.inspect} on #{self}"
      end

      def sole_multiton_assert_registry_empty!(setting)
        return if instance_count.zero?

        raise Internal::ConfigurationLockedError,
              "cannot change Multiton #{setting} after instances have been created; clear_instances first"
      end
    end

    private_constant :ClassMethods
  end
end
