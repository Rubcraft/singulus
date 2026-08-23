# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sole do
  def build_class(mode: :strict, &block)
    Class.new do
      include Sole::Singleton

      sole mode: mode
      class_eval(&block) if block
    end
  end

  describe ":standard mode" do
    let(:klass) { build_class(mode: :standard) }

    it "keeps Ruby Singleton semantics" do
      expect(klass.instance).to equal(klass.instance)
      expect { klass.new }.to raise_error(NoMethodError)
    end

    it "allows Singleton inheritance semantics" do
      expect { Class.new(klass) }.not_to raise_error
    end
  end

  describe ":strict mode" do
    let(:klass) { build_class(mode: :strict) }

    it "returns one instance" do
      expect(klass.instance).to equal(klass.instance)
    end

    it "blocks reflective constructor capture before instance" do
      expect { klass.method(:new) }.to raise_error(Sole::Error)
      expect { klass.method(:allocate) }.to raise_error(Sole::Error)
    end

    it "blocks send and __send__ before instance" do
      expect { klass.send(:new) }.to raise_error(Sole::Error)
      expect { klass.__send__(:allocate) }.to raise_error(Sole::Error)
    end

    it "seals constructors after instance" do
      klass.instance

      expect { klass.send(:new) }.to raise_error(Sole::Error)
      expect { klass.__send__(:allocate) }.to raise_error(Sole::Error)
    end

    it "prevents redefining constructors" do
      expect do
        klass.define_singleton_method(:new) { :bypass }
      end.to raise_error(Sole::Error)
    end

    it "prevents inheritance" do
      expect { Class.new(klass) }.to raise_error(Sole::Error)
    end

    it "remains thread-safe" do
      instances = Array.new(50) { Thread.new { klass.instance } }.map(&:value)
      expect(instances.map(&:object_id).uniq.length).to eq(1)
    end
  end

  describe ":runtime mode" do
    let(:klass) { build_class(mode: :runtime) }

    it "blocks Class#new obtained as an UnboundMethod" do
      constructor = Class.instance_method(:new)

      expect { constructor.bind(klass) }
        .to raise_error(Sole::Error)

      expect { constructor.bind_call(klass) }
        .to raise_error(Sole::Error)
    end

    it "blocks Class#allocate obtained as an UnboundMethod" do
      allocator = Class.instance_method(:allocate)

      expect { allocator.bind(klass) }
        .to raise_error(Sole::Error)
    end

    it "blocks binding reflection gateways to the protected class" do
      original_method = Object.instance_method(:method)
      original_send = BasicObject.instance_method(:__send__)

      expect { original_method.bind(klass) }
        .to raise_error(Sole::Error)

      expect { original_send.bind(klass) }
        .to raise_error(Sole::Error)
    end

    it "blocks bind_call through reflection gateways when accessing constructors" do
      original_method = Object.instance_method(:method)
      original_send = BasicObject.instance_method(:__send__)

      expect { original_method.bind_call(klass, :new) }
        .to raise_error(Sole::Error)

      expect { original_send.bind_call(klass, :allocate) }
        .to raise_error(Sole::Error)
    end

    it "blocks previously captured constructor Method invocation" do
      plain = Class.new
      captured = Class.instance_method(:new).bind(plain)
      plain.include Sole::Singleton

      plain.sole mode: :runtime

      expect { captured.call }
        .to raise_error(Sole::Error)
    end

    it "blocks turning dangerous Method objects into Proc objects" do
      plain = Class.new
      captured = Class.instance_method(:new).bind(plain)
      plain.include Sole::Singleton

      plain.sole mode: :runtime

      expect { captured.to_proc }
        .to raise_error(Sole::Error)
    end
  end

  describe "configuration" do
    after do
      described_class.reset_configuration!
    end

    it "defaults to strict" do
      expect(described_class.configuration.default_mode).to eq(:strict)
    end

    it "can make runtime mode the default" do
      described_class.configure { |config| config.default_mode = :runtime }

      klass = Class.new { include Sole::Singleton }

      expect(klass.sole_mode).to eq(:runtime)
    end

    it "rejects invalid modes" do
      expect do
        described_class.configure { |config| config.default_mode = :unknown }
      end.to raise_error(Sole::Error)
    end
  end

  describe ".with" do
    it "configures the mode directly from include" do
      klass = Class.new do
        include Sole::Singleton.with(:runtime)
      end

      expect(klass.sole_mode).to eq(:runtime)
    end

    it "accepts the keyword form" do
      klass = Class.new do
        include Sole::Singleton.with(mode: :standard)
      end

      expect(klass.sole_mode).to eq(:standard)
    end

    it "keeps configured includes independent" do
      strict_class = Class.new do
        include Sole::Singleton.with(:strict)
      end

      standard_class = Class.new do
        include Sole::Singleton.with(:standard)
      end

      expect(strict_class.sole_mode).to eq(:strict)
      expect(standard_class.sole_mode).to eq(:standard)
    end

    it "rejects ambiguous mode arguments" do
      expect { Sole::Singleton.with(:strict, mode: :runtime) }
        .to raise_error(ArgumentError)
    end

    it "rejects unsupported options" do
      expect { Sole::Singleton.with(foo: :bar) }
        .to raise_error(ArgumentError)
    end
  end
end
