# frozen_string_literal: true

if ENV["COVERAGE"] != "0"
  require "simplecov"
  SimpleCov.start do
    enable_coverage :branch
    skip "/spec/"
  end
end

require "lethe"
Dir[File.join(__dir__, "support", "*.rb")].sort.each { |file| require file }

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.include DatabaseHelpers

  config.before(:suite) { DatabaseHelpers.connect }

  config.before do
    Lethe.reset!
    I18n.locale = :en
  end
end
