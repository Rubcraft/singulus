# frozen_string_literal: true

require "spec_helper"

# Keyed identity, lifecycle, argument forwarding, and class-level policy.
RSpec.describe Singulus::Multiton do
  include MultitonHelpers

  after do
    Singulus.reset_configuration!
  end

  it "allows standard-mode duplication without an explicit retention strategy" do
    klass = build_multiton(mode: :standard) do
      def initialize(identifier)
        @identifier = identifier
      end
    end

    instance = klass.instance_for(:tenant)

    expect(klass.singulus_mode).to eq(:standard)
    expect(instance.dup).not_to equal(instance)
  end

  it "returns one instance per key" do
    klass = build_multiton do
      attr_reader :identifier

      def initialize(identifier)
        @identifier = identifier
      end
    end

    first = klass.instance_for(1)
    same = klass.instance_for(1)
    other = klass.instance_for(2)

    expect(first).to equal(same)
    expect(first).not_to equal(other)
  end

  it "is thread-safe for the same key" do
    klass = build_multiton do
      def initialize(identifier)
        @identifier = identifier
      end
    end

    instances = Array.new(50) { Thread.new { klass.instance_for(:tenant) } }.map(&:value)
    expect(instances.map(&:object_id).uniq.length).to eq(1)
  end

  it "allows a key normalizer" do
    klass = build_multiton do
      multiton_key { |tenant| tenant.fetch(:id) }

      def initialize(tenant)
        @tenant = tenant
      end
    end

    first = klass.instance_for({ id: 7, name: "A" })
    second = klass.instance_for({ id: 7, name: "B" })

    expect(first).to equal(second)
  end

  it "stabilizes String, Array and Hash keys" do
    klass = build_multiton do
      def initialize(identifier)
        @identifier = identifier
      end
    end

    tenant = +"tenant"
    region = +"ar"
    original_key = [tenant, { region: region }]

    first = klass.instance_for(original_key)

    tenant << "-changed"
    region << "-changed"

    expect(original_key).to eq(["tenant-changed", { region: "ar-changed" }])
    expect(klass.instance_for(["tenant", { region: "ar" }])).to equal(first)
  end

  it "supports explicit registry lifecycle" do
    klass = build_multiton do
      def initialize(identifier)
        @identifier = identifier
      end
    end

    first = klass.instance_for(1)

    expect(klass.instance?(1)).to be(true)
    expect(klass.instance_count).to eq(1)
    expect(klass.instance_keys).to eq([1])
    expect(klass.delete_instance(1)).to equal(first)
    expect(klass.instance?(1)).to be(false)
    expect(klass.instance_for(1)).not_to equal(first)
  end

  it "clears the registry and returns the removed count" do
    klass = build_multiton do
      def initialize(identifier)
        @identifier = identifier
      end
    end

    klass.instance_for(1)
    klass.instance_for(2)

    expect(klass.clear_instances).to eq(2)
    expect(klass.instance_count).to eq(0)
  end

  it "detects recursive initialization for the same key" do
    klass = nil
    klass = build_multiton do
      define_method(:initialize) do |identifier|
        klass.instance_for(identifier)
      end
    end

    expect { klass.instance_for(:recursive) }
      .to raise_error(Singulus::Error)
  end

  it "restores its constructor after a rejected mutation" do
    klass = build_multiton do
      def initialize(identifier)
        @identifier = identifier
      end
    end

    expect do
      klass.define_singleton_method(:new) { |_identifier| :bypass }
    end.to raise_error(Singulus::Error)

    expect(klass.instance_for(1)).to be_a(klass)
  end

  it "blocks direct constructor reflection in strict mode" do
    klass = build_multiton do
      def initialize(identifier)
        @identifier = identifier
      end
    end

    expect { klass.method(:new) }.to raise_error(Singulus::Error)
    expect { klass.send(:new, 1) }.to raise_error(Singulus::Error)
  end

  it "blocks duplication in hardened modes" do
    klass = build_multiton do
      def initialize(identifier)
        @identifier = identifier
      end
    end

    instance = klass.instance_for(1)

    expect { instance.dup }.to raise_error(Singulus::Error)
    expect { instance.clone }.to raise_error(Singulus::Error)
  end

  it "prevents inheritance in hardened modes" do
    klass = build_multiton
    expect { Class.new(klass) }.to raise_error(Singulus::Error)
  end

  describe ".with" do
    it "configures mode directly from include" do
      klass = Class.new do
        include Singulus::Multiton.with(:runtime)

        def initialize(identifier)
          @identifier = identifier
        end
      end

      expect(klass.singulus_mode).to eq(:runtime)
      expect(klass.instance_for(1)).to be_a(klass)
    end

    it "configures retention directly from include" do
      klass = Class.new do
        include Singulus::Multiton.with(
          :strict,
          retention: :lru,
          max_size: 2
        )

        def initialize(identifier)
          @identifier = identifier
        end
      end

      klass.instance_for(1)
      klass.instance_for(2)
      klass.instance_for(3)

      expect(klass.instance_keys).to eq([2, 3])
    end

    it "accepts the keyword mode form" do
      klass = Class.new do
        include Singulus::Multiton.with(
          mode: :strict,
          retention: :ttl,
          ttl: 60
        )
      end

      expect(klass.singulus_mode).to eq(:strict)
      expect(klass.multiton_retention).to eq(:ttl)
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

  describe "registry edge behavior" do
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

  describe "standard-mode operations" do
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

  describe "reflection policy" do
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

  it "keeps a non-constructor singleton method definition untouched in standard Multiton mode" do
    klass = Class.new do
      include Singulus::Multiton.with(:standard)

      def initialize(identifier)
        @identifier = identifier
      end
    end

    expect do
      klass.define_singleton_method(:health) { :ok }
    end.not_to raise_error

    expect(klass.health).to eq(:ok)
  end
end
