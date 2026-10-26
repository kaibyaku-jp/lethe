# frozen_string_literal: true

# A small social app for lethe's integration specs. It loads Active Storage
# so that has_one_attached is real, and keeps its database in tmp/.
require "rails"
require "active_record/railtie"
require "active_storage/engine"
require "lethe"

module SnsApp
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f
    config.eager_load = false
    config.logger = Logger.new(nil)
    config.secret_key_base = "lethe-fixture"
    config.active_storage.service = :local
    config.i18n.available_locales = %i[en ja]

    config.after_initialize do
      ActiveRecord::Schema.verbose = false
      load Rails.root.join("db/schema.rb")
    end
  end
end

Lethe.configure do |config|
  config.definition_path = ENV.fetch("LETHE_DEFINITION", "config/lethe.rb")
  config.export_path = ENV.fetch("LETHE_EXPORT", "tmp/lethe")
  config.guess_columns["User"] = %w[follower_id following_id]
end
