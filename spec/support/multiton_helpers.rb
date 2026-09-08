# frozen_string_literal: true

module MultitonHelpers
  def build_multiton(mode: :strict, retention: nil, ttl: nil, max_size: nil, &block)
    Class.new do
      include Singulus::Multiton

      singulus mode: mode, retention: retention, ttl: ttl, max_size: max_size
      class_eval(&block) if block
    end
  end
end
