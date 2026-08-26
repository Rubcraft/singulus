# frozen_string_literal: true

require "simplecov" if ENV.fetch("COVERAGE", "true") == "true"

require "singulus"

RSpec.configure do |config|
  config.order = :random
  Kernel.srand config.seed

  config.disable_monkey_patching!
  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end
end
