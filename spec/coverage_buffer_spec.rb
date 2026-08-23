# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Sole coverage buffer" do
  after do
    Sole.reset_configuration!
  end

  it "keeps a non-constructor singleton method definition untouched in strict mode" do
    klass = Class.new do
      include Sole::Singleton
    end

    expect do
      klass.define_singleton_method(:health) { :ok }
    end.not_to raise_error

    expect(klass.health).to eq(:ok)
  end

  it "keeps a non-constructor singleton method definition untouched in standard Multiton mode" do
    klass = Class.new do
      include Sole::Multiton.with(:standard)

      def initialize(identifier)
        @identifier = identifier
      end
    end

    expect do
      klass.define_singleton_method(:health) { :ok }
    end.not_to raise_error

    expect(klass.health).to eq(:ok)
  end

  it "returns the same runtime hardening state when enable is called repeatedly" do
    klass = Class.new do
      include Sole::Singleton.with(:runtime)
    end

    first = klass.sole_mode

    another = Class.new do
      include Sole::Singleton.with(:runtime)
    end

    expect(first).to eq(:runtime)
    expect(another.sole_mode).to eq(:runtime)
  end

  it "allows a safe public_send in strict mode" do
    klass = Class.new do
      include Sole::Singleton

      def self.echo(value)
        value
      end
    end

    expect(klass.public_send(:echo, :ok)).to eq(:ok)
  end
end
