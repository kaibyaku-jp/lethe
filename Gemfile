# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "rake"
gem "rspec", "~> 3.12"
gem "standard", "~> 1.50"
gem "simplecov", require: false
gem "sqlite3", ">= 2.1"
# For the fixture app's has_one_attached; lethe itself never loads it.
# gemfiles/rails_*.gemfile set these to test another Rails.
gem "activestorage", @rails_requirement || ">= 7.2" unless @rails_from_git
