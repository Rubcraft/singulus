# frozen_string_literal: true

module Singulus
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
          singulus_reject_binding!(object)
          super
        end

        def bind_call(object, *args, &)
          singulus_reject_bind_call!(object, args)
          super
        end

        private

        def singulus_reject_binding!(object)
          return unless Internal.runtime_hardened?(object)
          return unless Internal.constructor_name?(name) || RuntimeHardening.reflection_gateway?(name)

          raise ConstructorAccessError,
                "cannot bind #{owner}##{name} to runtime-hardened Singulus #{object}"
        end

        def singulus_reject_bind_call!(object, args)
          return unless Internal.runtime_hardened?(object)

          if Internal.constructor_name?(name)
            raise ConstructorAccessError,
                  "cannot invoke constructor #{owner}##{name} on runtime-hardened Singulus #{object}"
          end

          return unless RuntimeHardening.reflection_gateway?(name)
          return unless Internal.constructor_name?(args.first)

          raise ConstructorAccessError,
                "cannot use #{owner}##{name} to access constructor #{args.first.inspect} " \
                "on runtime-hardened Singulus #{object}"
        end
      end

      module MethodGuard
        def call(*args, &)
          singulus_reject_invocation!(args)
          super
        end

        def [](*args, &)
          singulus_reject_invocation!(args)
          super
        end

        def to_proc
          singulus_reject_transformation!
          super
        end

        def >>(other)
          singulus_reject_transformation!
          super
        end

        def <<(other)
          singulus_reject_transformation!
          super
        end

        private

        def singulus_reject_invocation!(args)
          return unless Internal.runtime_hardened?(receiver)

          if Internal.constructor_name?(name)
            raise ConstructorAccessError,
                  "constructor #{name.inspect} cannot be invoked for runtime-hardened Singulus #{receiver}"
          end

          return unless RuntimeHardening.reflection_gateway?(name)
          return unless Internal.constructor_name?(args.first)

          raise ConstructorAccessError,
                "#{name} cannot be used to access constructor #{args.first.inspect} " \
                "for runtime-hardened Singulus #{receiver}"
        end

        def singulus_reject_transformation!
          return unless Internal.runtime_hardened?(receiver)
          return unless Internal.constructor_name?(name) || RuntimeHardening.reflection_gateway?(name)

          raise ConstructorAccessError,
                "Method #{name.inspect} for runtime-hardened Singulus #{receiver} " \
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
