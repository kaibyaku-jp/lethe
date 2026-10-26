# frozen_string_literal: true

module Lethe
  # Adds the rake tasks, and nothing else: lethe does not run inside the application.
  class Railtie < Rails::Railtie
    rake_tasks do
      load File.expand_path("tasks/lethe.rake", __dir__)
    end
  end
end
