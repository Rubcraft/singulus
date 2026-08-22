# frozen_string_literal: true

module Sole
  module Internal
    module ConstructorGuard
    private

    def new(*args, **kwargs, &block)
      sole_reject_unauthorized_constructor!(:new)
      super
    end

    def allocate
      sole_reject_unauthorized_constructor!(:allocate)
      super
    end

    def sole_reject_unauthorized_constructor!(method_name)
      return unless Internal.locally_hardened?(self)
      return if Internal.constructor_access_allowed?(self)

      raise ConstructorAccessError,
            "constructor #{method_name.inspect} is inaccessible for #{Internal.kind_for(self)} #{self}"
    end
  end
end
end
