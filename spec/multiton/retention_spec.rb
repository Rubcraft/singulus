# frozen_string_literal: true

require "spec_helper"

# Retention validation and eviction semantics using a controlled clock.
RSpec.describe Singulus::Multiton do
  include MultitonHelpers

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

    allow(klass).to receive(:singulus_multiton_monotonic_time).and_return(100.0, 100.0, 200.0, 200.0)

    first = klass.instance_for(1)
    second = klass.instance_for(1)

    expect(second).not_to equal(first)
  end

  it "rejects invalid retention options" do
    expect { build_multiton(retention: :ttl) }
      .to raise_error(Singulus::Error)

    expect { build_multiton(retention: :lru, max_size: 0) }
      .to raise_error(Singulus::Error)

    expect { build_multiton(retention: :forever, ttl: 1) }
      .to raise_error(Singulus::Error)
  end

  it "locks key and retention configuration once instances exist" do
    klass = build_multiton do
      def initialize(identifier)
        @identifier = identifier
      end
    end

    klass.instance_for(1)

    expect { klass.multiton_key(&:to_s) }
      .to raise_error(Singulus::Error)
    expect { klass.multiton_retention(:lru, max_size: 10) }
      .to raise_error(Singulus::Error)
  end

  describe "advanced retention" do
    it "rejects max_size with ttl and points to bounded" do
      expect { build_multiton(retention: :ttl, ttl: 60, max_size: 3) }
        .to raise_error(Singulus::Error, /:bounded/)
    end

    it "rejects ttl with lru and points to bounded" do
      expect { build_multiton(retention: :lru, ttl: 60, max_size: 3) }
        .to raise_error(Singulus::Error, /:bounded/)
    end

    it "supports bounded retention with TTL and LRU limits" do
      klass = build_multiton(retention: :bounded, ttl: 60, max_size: 2) do
        def initialize(identifier)
          @identifier = identifier
        end
      end

      allow(klass).to receive(:singulus_multiton_monotonic_time).and_return(100.0)
      klass.instance_for(1)
      klass.instance_for(2)
      klass.instance_for(1)
      klass.instance_for(3)

      expect(klass.instance_keys).to eq([1, 3])

      allow(klass).to receive(:singulus_multiton_monotonic_time).and_return(200.0)
      expect(klass.instance_count).to eq(0)
    end

    it "requires both ttl and max_size for bounded retention" do
      expect { build_multiton(retention: :bounded, ttl: 60) }
        .to raise_error(Singulus::Error)
      expect { build_multiton(retention: :bounded, max_size: 3) }
        .to raise_error(Singulus::Error)
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
        .to raise_error(Singulus::Error)
    end
  end

  describe "retention configuration" do
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
  end

  describe "supported retention settings" do
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
