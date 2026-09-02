# frozen_string_literal: true

if ENV["COVERAGE"] == "true"
  require "simplecov"
  SimpleCov.start
end

require "singulus"

RSpec.configure do |config|
  config.order = :random
  Kernel.srand config.seed

  config.disable_monkey_patching!
  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end
end
