# frozen_string_literal: true

require_relative "lib/lethe/version"

Gem::Specification.new do |spec|
  spec.name = "lethe"
  spec.version = Lethe::VERSION
  spec.authors = ["KAIBYAKU K.K"]
  spec.summary = "Declare what happens to each table when a user leaves, and catch the ones you forgot"
  spec.description = <<~DESC
    lethe finds every table and column that points at a model such as User,
    from foreign keys, associations and column names, and checks that each one
    has a declared policy for when that user leaves: destroy, scrub, keep or
    ignore. It reads the schema only and never touches your data.
  DESC
  spec.homepage = "https://github.com/kaibyaku-jp/lethe"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.glob(["lib/**/*.{rb,rake,yml,tt}", "README.md", "LICENSE", "CHANGELOG.md"], base: __dir__)

  spec.add_dependency "activerecord", ">= 7.2", "< 9"
  spec.add_dependency "railties", ">= 7.2", "< 9"
end
