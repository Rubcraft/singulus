# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Singulus public API" do
  it "exposes only the supported root constants" do
    expect(Singulus.constants(false).sort).to eq(%i[Error Multiton Singleton VERSION])
  end

  it "exposes Singleton and Multiton" do
    expect(defined?(Singulus::Singleton)).to eq("constant")
    expect(defined?(Singulus::Multiton)).to eq("constant")
  end

  it "keeps implementation namespaces inaccessible" do
    expect { Singulus::Internal }.to raise_error(NameError)
    expect { Singulus::Configuration }.to raise_error(NameError)
    expect { Singulus::RuntimeHardening }.to raise_error(NameError)
    expect { Singulus::ConstructorGuard }.to raise_error(NameError)
  end

  it "exposes one public base error for rescuing Singulus failures" do
    expect(Singulus::Error).to be < StandardError
  end
end
