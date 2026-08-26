# frozen_string_literal: true

module Singulus
  module Internal
    module MutationGuard
      def singleton_method_added(method_name)
        return super if @__singulus_restoring_constructor__
        return super unless Internal.locally_hardened?(self)
        return super unless Internal.constructor_name?(method_name)

        singulus_restore_constructor!(method_name)

        raise ConstructorAccessError,
              "constructor #{method_name.inspect} cannot be redefined on #{Internal.kind_for(self)} #{self}"
      end

      private

      def singulus_restore_constructor!(method_name)
        @__singulus_restoring_constructor__ = true
        singleton_class.__send__(:remove_method, method_name)

        if Internal.sealed_singleton?(self)
          singleton_class.__send__(:undef_method, method_name)
        else
          private_class_method method_name
        end
      ensure
        @__singulus_restoring_constructor__ = false
      end
    end
  end
end
