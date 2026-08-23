# frozen_string_literal: true

module Sole
  module Internal
    module ReflectionGuard
      def method(method_name)
        sole_reject_constructor_access!(method_name)
        super
      end

      def public_method(method_name)
        sole_reject_constructor_access!(method_name)
        super
      end

      def singleton_method(method_name)
        sole_reject_constructor_access!(method_name)
        super
      end

      def send(method_name, ...)
        sole_reject_constructor_access!(method_name)
        super
      end

      def __send__(method_name, ...)
        sole_reject_constructor_access!(method_name)
        super
      end

      def public_send(method_name, ...)
        sole_reject_constructor_access!(method_name)
        super
      end

      private

      def sole_reject_constructor_access!(method_name)
        return unless Internal.locally_hardened?(self)
        return unless Internal.constructor_name?(method_name)

        raise ConstructorAccessError,
              "constructor #{method_name.inspect} is inaccessible for #{Internal.kind_for(self)} #{self}"
      end
    end
  end
end
