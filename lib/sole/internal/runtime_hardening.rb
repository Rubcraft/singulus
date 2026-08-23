# frozen_string_literal: true

module Sole
  module Internal
    module RuntimeHardening
      REFLECTION_GATEWAYS = %i[
        method
        public_method
        singleton_method
        send
        __send__
        public_send
      ].freeze

      module UnboundMethodGuard
        def bind(object)
          sole_reject_binding!(object)
          super
        end

        def bind_call(object, *args, &)
          sole_reject_bind_call!(object, args)
          super
        end

        private

        def sole_reject_binding!(object)
          return unless Internal.runtime_hardened?(object)
          return unless Internal.constructor_name?(name) || RuntimeHardening.reflection_gateway?(name)

          raise ConstructorAccessError,
                "cannot bind #{owner}##{name} to runtime-hardened Sole #{object}"
        end

        def sole_reject_bind_call!(object, args)
          return unless Internal.runtime_hardened?(object)

          if Internal.constructor_name?(name)
            raise ConstructorAccessError,
                  "cannot invoke constructor #{owner}##{name} on runtime-hardened Sole #{object}"
          end

          return unless RuntimeHardening.reflection_gateway?(name)
          return unless Internal.constructor_name?(args.first)

          raise ConstructorAccessError,
                "cannot use #{owner}##{name} to access constructor #{args.first.inspect} " \
                "on runtime-hardened Sole #{object}"
        end
      end

      module MethodGuard
        def call(*args, &)
          sole_reject_invocation!(args)
          super
        end

        def [](*args, &)
          sole_reject_invocation!(args)
          super
        end

        def to_proc
          sole_reject_transformation!
          super
        end

        def >>(other)
          sole_reject_transformation!
          super
        end

        def <<(other)
          sole_reject_transformation!
          super
        end

        private

        def sole_reject_invocation!(args)
          return unless Internal.runtime_hardened?(receiver)

          if Internal.constructor_name?(name)
            raise ConstructorAccessError,
                  "constructor #{name.inspect} cannot be invoked for runtime-hardened Sole #{receiver}"
          end

          return unless RuntimeHardening.reflection_gateway?(name)
          return unless Internal.constructor_name?(args.first)

          raise ConstructorAccessError,
                "#{name} cannot be used to access constructor #{args.first.inspect} " \
                "for runtime-hardened Sole #{receiver}"
        end

        def sole_reject_transformation!
          return unless Internal.runtime_hardened?(receiver)
          return unless Internal.constructor_name?(name) || RuntimeHardening.reflection_gateway?(name)

          raise ConstructorAccessError,
                "Method #{name.inspect} for runtime-hardened Sole #{receiver} " \
                "cannot be converted or composed"
        end
      end

      class << self
        def enable!
          mutex.synchronize do
            return if enabled?

            UnboundMethod.prepend(UnboundMethodGuard)
            Method.prepend(MethodGuard)

            @enabled = true
          end
        end

        def enabled?
          @enabled == true
        end

        def reflection_gateway?(method_name)
          REFLECTION_GATEWAYS.include?(Internal.normalize_method_name(method_name))
        end

        private

        def mutex
          @mutex ||= Thread::Mutex.new
        end
      end
    end
  end
end
