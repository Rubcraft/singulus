# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Singulus branch coverage contracts" do
  after do
    Singulus.reset_configuration!
  end

  describe "standard-mode fallthrough behavior" do
    it "falls through to Ruby Singleton duplication semantics in standard mode" do
      klass = Class.new do
        include Singulus::Singleton.with(:standard)
      end

      instance = klass.instance

      expect { instance.dup }.to raise_error(TypeError)
      expect { instance.clone }.to raise_error(TypeError)
    end

    it "preserves clone keyword forwarding for ordinary Multiton instances" do
      klass = Class.new do
        include Singulus::Multiton.with(:standard)

        def initialize(identifier)
          @identifier = identifier
        end
      end

      instance = klass.instance_for(1)
      cloned = instance.clone(freeze: false)

      expect(cloned).to be_a(klass)
      expect(cloned).not_to be_frozen
    end

    it "does not apply Singulus duplication rejection in standard Multiton mode" do
      klass = Class.new do
        include Singulus::Multiton.with(:standard)

        def initialize(identifier)
          @identifier = identifier
        end
      end

      instance = klass.instance_for(1)

      expect { instance.dup }.not_to raise_error
      expect { instance.clone }.not_to raise_error
    end

    it "allows constructor mutation logic to fall through in standard mode" do
      klass = Class.new do
        include Singulus::Multiton.with(:standard)

        def initialize(identifier)
          @identifier = identifier
        end
      end

      expect do
        klass.define_singleton_method(:new) do |identifier|
          allocate.tap { |object| object.send(:initialize, identifier) }
        end
      end.not_to raise_error
    end
  end

  describe "reflection guard fallthroughs" do
    it "allows non-constructor reflection on a hardened Multiton" do
      klass = Class.new do
        include Singulus::Multiton

        def self.health
          :ok
        end

        def initialize(identifier)
          @identifier = identifier
        end
      end

      expect(klass.method(:health).call).to eq(:ok)
      expect(klass.public_method(:health).call).to eq(:ok)
      expect(klass.singleton_method(:health).call).to eq(:ok)
      expect(klass.send(:health)).to eq(:ok)
      expect(klass.public_send(:health)).to eq(:ok)
    end

    it "allows reflective constructor access in standard Multiton mode" do
      klass = Class.new do
        include Singulus::Multiton.with(:standard)

        attr_reader :identifier

        def initialize(identifier)
          @identifier = identifier
        end
      end

      constructor = klass.method(:new)
      instance = constructor.call(:reflected)

      expect(instance).to be_a(klass)
      expect(instance.identifier).to eq(:reflected)
    end
  end

  describe "runtime-hardening negative branches" do
    it "does not block a captured constructor Method for a strict non-runtime class" do
      plain = Class.new
      captured = Class.instance_method(:new).bind(plain)

      plain.include Singulus::Singleton

      plain.singulus mode: :strict

      expect { captured.call }.not_to raise_error
    end

    it "does not block constructor UnboundMethod binding to a strict non-runtime class" do
      klass = Class.new do
        include Singulus::Singleton.with(:strict)
      end

      constructor = Class.instance_method(:new)

      expect { constructor.bind(klass) }.not_to raise_error
    end

    it "does not block composition of a safe Method on a runtime class" do
      klass = Class.new do
        include Singulus::Singleton.with(:runtime)

        def self.echo(value)
          value
        end
      end

      method = klass.method(:echo)
      identity = ->(value) { value }

      expect((method >> identity).call(:ok)).to eq(:ok)
      expect((method << identity).call(:ok)).to eq(:ok)
    end

    it "allows binding a safe non-gateway UnboundMethod to a runtime class" do
      klass = Class.new do
        include Singulus::Singleton.with(:runtime)
      end

      safe_unbound = Module.instance_method(:name)
      bound = safe_unbound.bind(klass)

      expect(bound.call).to be_nil
    end

    it "still blocks binding reflection gateways even when the eventual target could be safe" do
      klass = Class.new do
        include Singulus::Singleton.with(:runtime)
      end

      gateway = Object.instance_method(:method)

      expect { gateway.bind(klass) }.to raise_error(Singulus::Error)
    end
  end

  describe "additional runtime branch contracts" do
    it "allows safe UnboundMethod bind_call on a runtime class" do
      klass = Class.new do
        include Singulus::Singleton.with(:runtime)
      end

      safe_unbound = Module.instance_method(:name)

      expect(safe_unbound.bind_call(klass)).to be_nil
    end

    it "allows safe Method transformations on a strict non-runtime class" do
      klass = Class.new do
        include Singulus::Singleton.with(:strict)

        def self.echo(value)
          value
        end
      end

      method = klass.method(:echo)
      identity = ->(value) { value }

      expect(method.to_proc.call(:ok)).to eq(:ok)
      expect((method >> identity).call(:ok)).to eq(:ok)
      expect((method << identity).call(:ok)).to eq(:ok)
    end

    it "allows a runtime Method gateway call when the requested method is not a constructor" do
      klass = Class.new do
        include Singulus::Singleton.with(:runtime)

        def self.health
          :ok
        end
      end

      gateway = klass.method(:method)

      expect(gateway.call(:health).call).to eq(:ok)
    end
  end

  describe "configuration edge cases" do
    it "keeps configuration reset idempotent" do
      first = Singulus.reset_configuration!
      second = Singulus.reset_configuration!

      expect(first.default_mode).to eq(:strict)
      expect(second.default_mode).to eq(:strict)
      expect(second).not_to equal(first)
    end
  end

  describe "Multiton retention branches" do
    def multiton
      Class.new do
        include Singulus::Multiton

        def initialize(identifier)
          @identifier = identifier
        end
      end
    end

    it "accepts a valid positive TTL" do
      klass = multiton

      expect(klass.multiton_retention(:ttl, ttl: 1)).to equal(klass)
      expect(klass.multiton_retention).to eq(:ttl)
    end

    it "accepts a valid LRU capacity" do
      klass = multiton

      expect(klass.multiton_retention(:lru, max_size: 1)).to equal(klass)
      expect(klass.multiton_retention).to eq(:lru)
    end

    it "accepts valid bounded retention" do
      klass = multiton

      expect(klass.multiton_retention(:bounded, ttl: 1, max_size: 1)).to equal(klass)
      expect(klass.multiton_retention).to eq(:bounded)
    end

    it "accepts weak retention with no options" do
      klass = multiton

      expect(klass.multiton_retention(:weak)).to equal(klass)
      expect(klass.multiton_retention).to eq(:weak)
    end
  end
end
