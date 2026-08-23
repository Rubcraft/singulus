# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sole::Multiton do
  def build_multiton(mode: :strict, retention: nil, ttl: nil, max_size: nil, &block)
    Class.new do
      include Sole::Multiton

      sole mode: mode, retention: retention, ttl: ttl, max_size: max_size if retention
      class_eval(&block) if block
    end
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

  it "supports LRU retention" do
    klass = build_multiton(retention: :lru, max_size: 2) do
      def initialize(identifier)
        @identifier = identifier
      end
    end

    klass.instance_for(1)
    klass.instance_for(2)
    klass.instance_for(1)
    klass.instance_for(3)

    expect(klass.instance_keys).to eq([1, 3])
  end

  it "supports TTL retention without sleeping" do
    klass = build_multiton(retention: :ttl, ttl: 60) do
      def initialize(identifier)
        @identifier = identifier
      end
    end

    allow(klass).to receive(:sole_multiton_monotonic_time).and_return(100.0, 100.0, 200.0, 200.0)

    first = klass.instance_for(1)
    second = klass.instance_for(1)

    expect(second).not_to equal(first)
  end

  it "rejects invalid retention options" do
    expect { build_multiton(retention: :ttl) }
      .to raise_error(Sole::Error)

    expect { build_multiton(retention: :lru, max_size: 0) }
      .to raise_error(Sole::Error)

    expect { build_multiton(retention: :forever, ttl: 1) }
      .to raise_error(Sole::Error)
  end

  it "locks key and retention configuration once instances exist" do
    klass = build_multiton do
      def initialize(identifier)
        @identifier = identifier
      end
    end

    klass.instance_for(1)

    expect { klass.multiton_key(&:to_s) }
      .to raise_error(Sole::Error)
    expect { klass.multiton_retention(:lru, max_size: 10) }
      .to raise_error(Sole::Error)
  end

  it "detects recursive initialization for the same key" do
    klass = nil
    klass = build_multiton do
      define_method(:initialize) do |identifier|
        klass.instance_for(identifier)
      end
    end

    expect { klass.instance_for(:recursive) }
      .to raise_error(Sole::Error)
  end

  it "restores its constructor after a rejected mutation" do
    klass = build_multiton do
      def initialize(identifier)
        @identifier = identifier
      end
    end

    expect do
      klass.define_singleton_method(:new) { |_identifier| :bypass }
    end.to raise_error(Sole::Error)

    expect(klass.instance_for(1)).to be_a(klass)
  end

  it "blocks direct constructor reflection in strict mode" do
    klass = build_multiton do
      def initialize(identifier)
        @identifier = identifier
      end
    end

    expect { klass.method(:new) }.to raise_error(Sole::Error)
    expect { klass.send(:new, 1) }.to raise_error(Sole::Error)
  end

  it "blocks duplication in hardened modes" do
    klass = build_multiton do
      def initialize(identifier)
        @identifier = identifier
      end
    end

    instance = klass.instance_for(1)

    expect { instance.dup }.to raise_error(Sole::Error)
    expect { instance.clone }.to raise_error(Sole::Error)
  end

  it "prevents inheritance in hardened modes" do
    klass = build_multiton
    expect { Class.new(klass) }.to raise_error(Sole::Error)
  end

  describe ".with" do
    it "configures mode directly from include" do
      klass = Class.new do
        include Sole::Multiton.with(:runtime)

        def initialize(identifier)
          @identifier = identifier
        end
      end

      expect(klass.sole_mode).to eq(:runtime)
      expect(klass.instance_for(1)).to be_a(klass)
    end

    it "configures retention directly from include" do
      klass = Class.new do
        include Sole::Multiton.with(
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
        include Sole::Multiton.with(
          mode: :strict,
          retention: :ttl,
          ttl: 60
        )
      end

      expect(klass.sole_mode).to eq(:strict)
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

  describe "advanced retention" do
    it "rejects max_size with ttl and points to bounded" do
      expect { build_multiton(retention: :ttl, ttl: 60, max_size: 3) }
        .to raise_error(Sole::Error, /:bounded/)
    end

    it "rejects ttl with lru and points to bounded" do
      expect { build_multiton(retention: :lru, ttl: 60, max_size: 3) }
        .to raise_error(Sole::Error, /:bounded/)
    end

    it "supports bounded retention with TTL and LRU limits" do
      klass = build_multiton(retention: :bounded, ttl: 60, max_size: 2) do
        def initialize(identifier)
          @identifier = identifier
        end
      end

      allow(klass).to receive(:sole_multiton_monotonic_time).and_return(100.0)
      klass.instance_for(1)
      klass.instance_for(2)
      klass.instance_for(1)
      klass.instance_for(3)

      expect(klass.instance_keys).to eq([1, 3])

      allow(klass).to receive(:sole_multiton_monotonic_time).and_return(200.0)
      expect(klass.instance_count).to eq(0)
    end

    it "requires both ttl and max_size for bounded retention" do
      expect { build_multiton(retention: :bounded, ttl: 60) }
        .to raise_error(Sole::Error)
      expect { build_multiton(retention: :bounded, max_size: 3) }
        .to raise_error(Sole::Error)
    end

    it "supports weak retention without accepting ttl or max_size" do
      klass = build_multiton(retention: :weak) do
        def initialize(identifier)
          @identifier = identifier
        end
      end

      first = klass.instance_for(1)
      expect(klass.instance_for(1)).to equal(first)
      expect { klass.multiton_retention(:weak, ttl: 1) }
        .to raise_error(Sole::Error)
    end
  end
end
