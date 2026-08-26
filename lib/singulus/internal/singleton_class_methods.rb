# frozen_string_literal: true

module Singulus
  module Internal
    module SingletonClassMethods
      def instance
        return super unless Internal.locally_hardened?(self)

        instance = Internal.with_constructor_access(self) { super }
        singulus_seal_constructors!
        instance
      end

      def singulus(mode:)
        Internal.set_mode!(self, mode)
        self
      end

      def singulus_mode
        Internal.mode_for(self)
      end

      private

      def inherited(subclass)
        if Internal.locally_hardened?(self)
          raise InheritanceError,
                "#{self} is a Singulus in #{singulus_mode.inspect} mode and cannot be subclassed"
        end

        super
      end

      def singulus_seal_constructors!
        return if singulus_sealed?

        singulus_seal_mutex.synchronize do
          return if singulus_sealed?

          singulus_seal_constructor!(:new)
          singulus_seal_constructor!(:allocate)

          @__singulus_sealed__ = true
        end
      end

      def singulus_seal_constructor!(method_name)
        singleton_class.__send__(:undef_method, method_name)
      rescue NameError
        return unless respond_to?(method_name, true)

        raise
      end

      def singulus_sealed?
        @__singulus_sealed__ == true
      end

      def singulus_seal_mutex
        @__singulus_seal_mutex__ ||= Thread::Mutex.new
      end
    end
  end
end
