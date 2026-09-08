# frozen_string_literal: true

require "spec_helper"

# Process-wide reflection guards must reject bypasses while preserving safe calls.
RSpec.describe "runtime hardening" do
  def build_class(mode: :strict, &block)
    Class.new do
      include Singulus::Singleton

      singulus mode: mode
      class_eval(&block) if block
    end
  end

  def runtime_multiton
    Class.new do
      include Singulus::Multiton

      singulus mode: :runtime

      def initialize(identifier)
        @identifier = identifier
      end
    end
  end

  it "blocks constructor UnboundMethod binding to a runtime Multiton" do
    klass = runtime_multiton
    constructor = Class.instance_method(:new)
    allocator = Class.instance_method(:allocate)

    expect { constructor.bind(klass) }.to raise_error(Singulus::Error)
    expect { constructor.bind_call(klass, 1) }.to raise_error(Singulus::Error)
    expect { allocator.bind(klass) }.to raise_error(Singulus::Error)
  end

  it "blocks captured reflection gateways" do
    klass = runtime_multiton
    original_method = Object.instance_method(:method)
    original_send = BasicObject.instance_method(:__send__)

    expect { original_method.bind_call(klass, :new) }
      .to raise_error(Singulus::Error)
    expect { original_send.bind_call(klass, :allocate) }
      .to raise_error(Singulus::Error)
  end

  it "blocks a Method captured before the class becomes runtime hardened" do
    klass = Class.new do
      def initialize(identifier)
        @identifier = identifier
      end
    end
    captured = Class.instance_method(:new).bind(klass)

    klass.include Singulus::Multiton
    klass.singulus mode: :runtime

    expect { captured.call(1) }.to raise_error(Singulus::Error)
    expect { captured[1] }.to raise_error(Singulus::Error)
    expect { captured.to_proc }.to raise_error(Singulus::Error)
  end

  describe ":runtime mode" do
    let(:klass) { build_class(mode: :runtime) }

    it "blocks Class#new obtained as an UnboundMethod" do
      constructor = Class.instance_method(:new)

      expect { constructor.bind(klass) }
        .to raise_error(Singulus::Error)

      expect { constructor.bind_call(klass) }
        .to raise_error(Singulus::Error)
    end

    it "blocks Class#allocate obtained as an UnboundMethod" do
      allocator = Class.instance_method(:allocate)

      expect { allocator.bind(klass) }
        .to raise_error(Singulus::Error)
    end

    it "blocks binding reflection gateways to the protected class" do
      original_method = Object.instance_method(:method)
      original_send = BasicObject.instance_method(:__send__)

      expect { original_method.bind(klass) }
        .to raise_error(Singulus::Error)

      expect { original_send.bind(klass) }
        .to raise_error(Singulus::Error)
    end

    it "blocks bind_call through reflection gateways when accessing constructors" do
      original_method = Object.instance_method(:method)
      original_send = BasicObject.instance_method(:__send__)

      expect { original_method.bind_call(klass, :new) }
        .to raise_error(Singulus::Error)

      expect { original_send.bind_call(klass, :allocate) }
        .to raise_error(Singulus::Error)
    end

    it "blocks previously captured constructor Method invocation" do
      plain = Class.new
      captured = Class.instance_method(:new).bind(plain)
      plain.include Singulus::Singleton

      plain.singulus mode: :runtime

      expect { captured.call }
        .to raise_error(Singulus::Error)
    end

    it "blocks turning dangerous Method objects into Proc objects" do
      plain = Class.new
      captured = Class.instance_method(:new).bind(plain)
      plain.include Singulus::Singleton

      plain.singulus mode: :runtime

      expect { captured.to_proc }
        .to raise_error(Singulus::Error)
    end
  end

  describe "runtime hardening public gateways" do
    def runtime_class
      Class.new do
        include Singulus::Singleton.with(:runtime)
      end
    end

    it "blocks public reflection gateways for constructors" do
      klass = runtime_class

      expect { klass.public_method(:new) }.to raise_error(Singulus::Error)
      expect { klass.singleton_method(:allocate) }.to raise_error(Singulus::Error)
      expect { klass.public_send(:new) }.to raise_error(Singulus::Error)
    end

    it "blocks composition when the captured constructor Method is the receiver" do
      plain = Class.new
      captured = Class.instance_method(:new).bind(plain)
      plain.include Singulus::Singleton

      plain.singulus mode: :runtime
      identity = ->(value) { value }

      expect { captured >> identity }.to raise_error(Singulus::Error)
      expect { captured << identity }.to raise_error(Singulus::Error)
    end

    it "blocks invocation through a Proc composition containing a captured constructor Method" do
      plain = Class.new
      captured = Class.instance_method(:new).bind(plain)
      plain.include Singulus::Singleton

      plain.singulus mode: :runtime

      composed = ->(value) { value } << captured

      expect { composed.call }.to raise_error(Singulus::Error)
    end

    it "does not reject a non-constructor Method on a runtime-hardened class" do
      klass = runtime_class
      klass.define_singleton_method(:health) { :ok }
      method = klass.method(:health)

      expect(method.call).to eq(:ok)
      expect(method[]).to eq(:ok)
      expect(method.to_proc.call).to eq(:ok)
    end
  end

  describe "runtime policy boundaries" do
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

  describe "safe runtime operations" do
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

  it "returns the same runtime hardening state when enable is called repeatedly" do
    klass = Class.new do
      include Singulus::Singleton.with(:runtime)
    end

    first = klass.singulus_mode

    another = Class.new do
      include Singulus::Singleton.with(:runtime)
    end

    expect(first).to eq(:runtime)
    expect(another.singulus_mode).to eq(:runtime)
  end
end
