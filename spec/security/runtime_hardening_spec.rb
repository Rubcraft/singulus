# frozen_string_literal: true

require "spec_helper"

RSpec.describe "runtime hardening" do
  def runtime_multiton
    Class.new do
      include Sole::Multiton

      sole mode: :runtime

      def initialize(identifier)
        @identifier = identifier
      end
    end
  end

  it "blocks constructor UnboundMethod binding to a runtime Multiton" do
    klass = runtime_multiton
    constructor = Class.instance_method(:new)
    allocator = Class.instance_method(:allocate)

    expect { constructor.bind(klass) }.to raise_error(Sole::Error)
    expect { constructor.bind_call(klass, 1) }.to raise_error(Sole::Error)
    expect { allocator.bind(klass) }.to raise_error(Sole::Error)
  end

  it "blocks captured reflection gateways" do
    klass = runtime_multiton
    original_method = Object.instance_method(:method)
    original_send = BasicObject.instance_method(:__send__)

    expect { original_method.bind_call(klass, :new) }
      .to raise_error(Sole::Error)
    expect { original_send.bind_call(klass, :allocate) }
      .to raise_error(Sole::Error)
  end

  it "blocks a Method captured before the class becomes runtime hardened" do
    klass = Class.new do
      def initialize(identifier)
        @identifier = identifier
      end
    end
    captured = Class.instance_method(:new).bind(klass)

    klass.include Sole::Multiton
    klass.sole mode: :runtime

    expect { captured.call(1) }.to raise_error(Sole::Error)
    expect { captured[1] }.to raise_error(Sole::Error)
    expect { captured.to_proc }.to raise_error(Sole::Error)
  end
end
