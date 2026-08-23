# frozen_string_literal: true

module Sole
  module Internal
    module InstanceGuard
      def dup
        sole_reject_duplication!(:duplicated)
        super
      end

      def clone(**options)
        sole_reject_duplication!(:cloned)
        return super() if options.empty?

        super
      end

      def initialize_dup(other)
        sole_reject_duplication!(:duplicated)
        super
      end

      def initialize_clone(other, **kwargs)
        sole_reject_duplication!(:cloned)
        super
      end

      private

      def sole_reject_duplication!(operation)
        return unless Internal.locally_hardened?(self.class)

        raise DuplicationError, "#{self.class} instance cannot be #{operation} in hardened mode"
      end
    end
  end
end
