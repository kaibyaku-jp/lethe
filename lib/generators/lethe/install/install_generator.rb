# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module Lethe
  module Generators
    # bin/rails generate lethe:install: the lethe_erasures table and a
    # config/lethe.rb to start from.
    class InstallGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      def create_migration_file
        migration_template "create_lethe_erasures.rb.tt", File.join(db_migrate_path, "create_lethe_erasures.rb")
      end

      def create_definitions
        template "lethe.rb.tt", "config/lethe.rb", skip: true
      end
    end
  end
end
