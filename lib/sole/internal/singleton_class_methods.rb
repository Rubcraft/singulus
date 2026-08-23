# frozen_string_literal: true

module Sole
  module Internal
    module SingletonClassMethods
      def instance
        return super unless Internal.locally_hardened?(self)

        instance = Internal.with_constructor_access(self) { super }
        sole_seal_constructors!
        instance
      end

      def sole(mode:)
        Internal.set_mode!(self, mode)
        self
      end

      def sole_mode
        Internal.mode_for(self)
      end

      private

      def inherited(subclass)
        if Internal.locally_hardened?(self)
          raise InheritanceError,
                "#{self} is a Sole in #{sole_mode.inspect} mode and cannot be subclassed"
        end

        super
      end

      def sole_seal_constructors!
        return if sole_sealed?

        sole_seal_mutex.synchronize do
          return if sole_sealed?

          sole_seal_constructor!(:new)
          sole_seal_constructor!(:allocate)

          @__sole_sealed__ = true
        end
      end

      def sole_seal_constructor!(method_name)
        singleton_class.__send__(:undef_method, method_name)
      rescue NameError
        return unless respond_to?(method_name, true)

        raise
      end

      def sole_sealed?
        @__sole_sealed__ == true
      end

      def sole_seal_mutex
        @__sole_seal_mutex__ ||= Thread::Mutex.new
      end
    end
  end
end
