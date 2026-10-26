# frozen_string_literal: true

# Exit only on failure, so that the tasks can be chained:
#   bin/rails lethe:check lethe:export
namespace :lethe do
  desc "Check that everything pointing at a subject has a policy (FORMAT=text|github|json STRICT=1 LOCALE=en|ja)"
  task check: :environment do
    Rails.application.eager_load!
    status = Lethe::Runner.new(root: Rails.root).check
    exit status unless status.zero?
  end

  desc "Write what happens to each kind of data when a subject leaves (CHECK=1 to compare instead, LOCALE=en|ja)"
  task export: :environment do
    Rails.application.eager_load!
    status = Lethe::Runner.new(root: Rails.root).export
    exit status unless status.zero?
  end

  desc "Delete kept rows whose `for:` has passed since their subject was erased"
  task sweep: :environment do
    Rails.application.eager_load!
    status = Lethe::Runner.new(root: Rails.root).sweep
    exit status unless status.zero?
  end
end
