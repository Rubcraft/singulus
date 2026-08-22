# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Sole public API" do
  it "exposes only the supported root constants" do
    expect(Sole.constants(false).sort).to eq(%i[Error Multiton Singleton VERSION])
  end

  it "exposes Singleton and Multiton" do
    expect(defined?(Sole::Singleton)).to eq("constant")
    expect(defined?(Sole::Multiton)).to eq("constant")
  end

  it "keeps implementation namespaces inaccessible" do
    expect { Sole::Internal }.to raise_error(NameError)
    expect { Sole::Configuration }.to raise_error(NameError)
    expect { Sole::RuntimeHardening }.to raise_error(NameError)
    expect { Sole::ConstructorGuard }.to raise_error(NameError)
  end

  it "exposes one public base error for rescuing Sole failures" do
    expect(Sole::Error).to be < StandardError
  end
end
