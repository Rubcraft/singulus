# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)

RuboCop::RakeTask.new(:rubocop) do |task|
  task.options = ["--parallel"]
end

desc "Run the complete local CI suite"
task ci: %i[rubocop spec]

task default: :ci
