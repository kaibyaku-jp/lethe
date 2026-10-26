# frozen_string_literal: true

require "rspec/core/rake_task"
require "standard/rake"

RSpec::Core::RakeTask.new(:spec)

task default: %i[spec standard]

desc "Build the gem into pkg/"
task :package do
  require "fileutils"
  require_relative "lib/lethe/version"
  FileUtils.mkdir_p("pkg")
  sh "gem", "build", "lethe.gemspec", "--output", "pkg/lethe-#{Lethe::VERSION}.gem"
end
