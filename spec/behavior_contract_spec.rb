# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Singulus behavior contracts" do
  after do
    Singulus.reset_configuration!
  end

  describe "configuration facade" do
    it "requires a block" do
      expect { Singulus.configure }.to raise_error(ArgumentError, /block is required/)
    end

    it "returns the configuration object and accepts string-compatible modes" do
      configuration = Singulus.configure { |config| config.default_mode = "standard" }

      expect(configuration).to equal(Singulus.configuration)
      expect(configuration.default_mode).to eq(:standard)
    end

    it "rejects objects that cannot be normalized to a mode" do
      expect do
        Singulus.configure { |config| config.default_mode = Object.new }
      end.to raise_error(Singulus::Error)
    end

    it "can reset configuration after customization" do
      Singulus.configure { |config| config.default_mode = :standard }

      Singulus.reset_configuration!

      expect(Singulus.configuration.default_mode).to eq(:strict)
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

  describe "Multiton registry edge behavior" do
    def build_multiton(mode: :strict, &block)
      Class.new do
        include Singulus::Multiton.with(mode: mode)

        class_eval(&block) if block
      end
    end

    it "uses the configured default mode when .with has no explicit mode" do
      Singulus.configure { |config| config.default_mode = :standard }

      klass = Class.new do
        include Singulus::Multiton.with

        def initialize(identifier)
          @identifier = identifier
        end
      end

      expect(klass.singulus_mode).to eq(:standard)
    end

    it "reports absence and deletion of a missing identifier" do
      klass = build_multiton do
        def initialize(identifier)
          @identifier = identifier
        end
      end

      expect(klass.instance?(:missing)).to be(false)
      expect(klass.delete_instance(:missing)).to be_nil
      expect(klass.clear_instances).to eq(0)
    end

    it "returns the current key normalizer and retention configuration" do
      klass = build_multiton
      normalizer = lambda(&:to_s)

      expect(klass.multiton_key).to be_nil
      expect(klass.multiton_key(&normalizer)).to equal(klass)
      expect(klass.multiton_key).to equal(normalizer)
      expect(klass.multiton_retention).to eq(:forever)
      expect(klass.multiton_retention(:lru, max_size: 3)).to equal(klass)
      expect(klass.multiton_retention).to eq(:lru)
    end

    it "rejects an unknown retention strategy" do
      klass = build_multiton

      expect { klass.multiton_retention(:unknown) }
        .to raise_error(Singulus::Error, /invalid Multiton retention/)
    end

    it "rejects every invalid forever and weak option combination" do
      forever = build_multiton
      weak = build_multiton

      expect { forever.multiton_retention(:forever, max_size: 1) }.to raise_error(Singulus::Error)
      expect { weak.multiton_retention(:weak, max_size: 1) }.to raise_error(Singulus::Error)
    end

    it "rejects non-positive TTL and missing LRU capacity" do
      ttl = build_multiton
      lru = build_multiton

      expect { ttl.multiton_retention(:ttl, ttl: 0) }.to raise_error(Singulus::Error)
      expect { lru.multiton_retention(:lru) }.to raise_error(Singulus::Error)
    end

    it "forwards additional positional arguments, keyword arguments and a block once" do
      klass = build_multiton do
        attr_reader :payload

        def initialize(identifier, extra, flag:)
          @payload = [identifier, extra, flag, yield]
        end
      end

      first = klass.instance_for(:id, "extra", flag: true) { :from_block }
      second = klass.instance_for(:id, "ignored", flag: false) { :ignored }

      expect(first.payload).to eq([:id, "extra", true, :from_block])
      expect(second).to equal(first)
    end

    it "permits inheritance in standard mode and initializes an independent child registry" do
      parent = build_multiton(mode: :standard) do
        def initialize(identifier)
          @identifier = identifier
        end
      end
      child = Class.new(parent)

      parent_instance = parent.instance_for(1)
      child_instance = child.instance_for(1)

      expect(child_instance).to be_a(child)
      expect(child_instance).not_to equal(parent_instance)
      expect(parent.instance_count).to eq(1)
      expect(child.instance_count).to eq(1)
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
end
