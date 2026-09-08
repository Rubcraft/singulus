# frozen_string_literal: true

require "spec_helper"

# Singleton identity, inclusion options, and local constructor policy.
RSpec.describe Singulus::Singleton do
  def build_class(mode: :strict, &block)
    Class.new do
      include Singulus::Singleton

      singulus mode: mode
      class_eval(&block) if block
    end
  end

  after do
    Singulus.reset_configuration!
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
      expect { klass.method(:new) }.to raise_error(Singulus::Error)
      expect { klass.method(:allocate) }.to raise_error(Singulus::Error)
    end

    it "blocks send and __send__ before instance" do
      expect { klass.send(:new) }.to raise_error(Singulus::Error)
      expect { klass.__send__(:allocate) }.to raise_error(Singulus::Error)
    end

    it "seals constructors after instance" do
      klass.instance

      expect { klass.send(:new) }.to raise_error(Singulus::Error)
      expect { klass.__send__(:allocate) }.to raise_error(Singulus::Error)
    end

    it "prevents redefining constructors" do
      expect do
        klass.define_singleton_method(:new) { :bypass }
      end.to raise_error(Singulus::Error)
    end

    it "prevents inheritance" do
      expect { Class.new(klass) }.to raise_error(Singulus::Error)
    end

    it "remains thread-safe" do
      instances = Array.new(50) { Thread.new { klass.instance } }.map(&:value)
      expect(instances.map(&:object_id).uniq.length).to eq(1)
    end
  end

  describe ".with" do
    it "configures the mode directly from include" do
      klass = Class.new do
        include Singulus::Singleton.with(:runtime)
      end

      expect(klass.singulus_mode).to eq(:runtime)
    end

    it "accepts the keyword form" do
      klass = Class.new do
        include Singulus::Singleton.with(mode: :standard)
      end

      expect(klass.singulus_mode).to eq(:standard)
    end

    it "keeps configured includes independent" do
      strict_class = Class.new do
        include Singulus::Singleton.with(:strict)
      end

      standard_class = Class.new do
        include Singulus::Singleton.with(:standard)
      end

      expect(strict_class.singulus_mode).to eq(:strict)
      expect(standard_class.singulus_mode).to eq(:standard)
    end

    it "rejects ambiguous mode arguments" do
      expect { described_class.with(:strict, mode: :runtime) }
        .to raise_error(ArgumentError)
    end

    it "rejects unsupported options" do
      expect { described_class.with(foo: :bar) }
        .to raise_error(ArgumentError)
    end
  end

  describe "Singleton public behavior" do
    it "uses the configured default mode when .with has no explicit mode" do
      Singulus.configure { |config| config.default_mode = :standard }

      klass = Class.new do
        include Singulus::Singleton.with
      end

      expect(klass.singulus_mode).to eq(:standard)
    end

    it "allows a strict class to switch to standard before it is sealed" do
      klass = Class.new do
        include Singulus::Singleton
      end

      expect(klass.singulus(mode: :standard)).to equal(klass)
      expect(klass.singulus_mode).to eq(:standard)
    end

    it "rejects a strict-to-standard downgrade after the singleton is sealed" do
      klass = Class.new do
        include Singulus::Singleton
      end

      klass.instance

      expect { klass.singulus(mode: :standard) }.to raise_error(Singulus::Error)
    end

    it "allows non-constructor reflection through the guards" do
      klass = Class.new do
        include Singulus::Singleton

        def self.health
          :ok
        end
      end

      expect(klass.method(:health).call).to eq(:ok)
      expect(klass.public_method(:health).call).to eq(:ok)
      expect(klass.singleton_method(:health).call).to eq(:ok)
      expect(klass.send(:health)).to eq(:ok)
      expect(klass.public_send(:health)).to eq(:ok)
    end
  end

  describe "standard duplication" do
    it "falls through to Ruby Singleton duplication semantics in standard mode" do
      klass = Class.new do
        include Singulus::Singleton.with(:standard)
      end

      instance = klass.instance

      expect { instance.dup }.to raise_error(TypeError)
      expect { instance.clone }.to raise_error(TypeError)
    end
  end

  it "keeps a non-constructor singleton method definition untouched in strict mode" do
    klass = Class.new do
      include Singulus::Singleton
    end

    expect do
      klass.define_singleton_method(:health) { :ok }
    end.not_to raise_error

    expect(klass.health).to eq(:ok)
  end

  it "allows a safe public_send in strict mode" do
    klass = Class.new do
      include Singulus::Singleton

      def self.echo(value)
        value
      end
    end

    expect(klass.public_send(:echo, :ok)).to eq(:ok)
  end
end
