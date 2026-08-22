# frozen_string_literal: true

SimpleCov.start do
  enable_coverage :branch
  primary_coverage :line

  add_filter "/spec/"
  add_filter "/vendor/"

  add_group "Core", "lib/sole.rb"
  add_group "Components", "lib/sole"

  track_files "lib/**/*.rb"

  minimum_coverage line: 95, branch: 90
  refuse_coverage_drop
end
