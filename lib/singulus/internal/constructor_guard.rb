# frozen_string_literal: true

module Singulus
  module Internal
    module ConstructorGuard
      private

      def new(...)
        singulus_reject_unauthorized_constructor!(:new)
        super
      end

      def allocate
        singulus_reject_unauthorized_constructor!(:allocate)
        super
      end

      def singulus_reject_unauthorized_constructor!(method_name)
        return unless Internal.locally_hardened?(self)
        return if Internal.constructor_access_allowed?(self)

        raise ConstructorAccessError,
              "constructor #{method_name.inspect} is inaccessible for #{Internal.kind_for(self)} #{self}"
      end
    end
  end
end
