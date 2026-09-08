# frozen_string_literal: true

require "spec_helper"

# Global defaults and reset behavior, isolated from class-level policy.
RSpec.describe Singulus do
  after do
    described_class.reset_configuration!
  end

  describe "configuration" do
    it "defaults to strict" do
      expect(described_class.configuration.default_mode).to eq(:strict)
    end

    it "can make runtime mode the default" do
      described_class.configure { |config| config.default_mode = :runtime }

      klass = Class.new { include Singulus::Singleton }

      expect(klass.singulus_mode).to eq(:runtime)
    end

    it "rejects invalid modes" do
      expect do
        described_class.configure { |config| config.default_mode = :unknown }
      end.to raise_error(Singulus::Error)
    end
  end

  describe "configuration facade" do
    it "requires a block" do
      expect { described_class.configure }.to raise_error(ArgumentError, /block is required/)
    end

    it "returns the configuration object and accepts string-compatible modes" do
      configuration = described_class.configure { |config| config.default_mode = "standard" }

      expect(configuration).to equal(described_class.configuration)
      expect(configuration.default_mode).to eq(:standard)
    end

    it "rejects objects that cannot be normalized to a mode" do
      expect do
        described_class.configure { |config| config.default_mode = Object.new }
      end.to raise_error(Singulus::Error)
    end

    it "can reset configuration after customization" do
      described_class.configure { |config| config.default_mode = :standard }

      described_class.reset_configuration!

      expect(described_class.configuration.default_mode).to eq(:strict)
    end
  end

  describe "configuration edge cases" do
    it "keeps configuration reset idempotent" do
      first = described_class.reset_configuration!
      second = described_class.reset_configuration!

      expect(first.default_mode).to eq(:strict)
      expect(second.default_mode).to eq(:strict)
      expect(second).not_to equal(first)
    end
  end
end
