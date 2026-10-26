# frozen_string_literal: true

require "tmpdir"

# A fresh schema for each example, on SQLite by default.
# Set DATABASE_URL to run the same specs on MySQL or PostgreSQL.
module DatabaseHelpers
  # A file rather than :memory:, where every connection the pool hands out
  # would be a different, empty database.
  SQLITE_PATH = File.join(Dir.tmpdir, "lethe-spec-#{Process.pid}.sqlite3")

  def self.connect
    url = ENV.fetch("DATABASE_URL") do
      File.delete(SQLITE_PATH) if File.exist?(SQLITE_PATH)
      at_exit { File.delete(SQLITE_PATH) if File.exist?(SQLITE_PATH) }
      "sqlite3:#{SQLITE_PATH}"
    end
    ActiveRecord::Base.establish_connection(url)
    ActiveRecord::Schema.verbose = false
  end

  def connection
    ActiveRecord::Base.lease_connection
  end

  # Drops every table, then defines the schema in the block.
  def schema(&block)
    connection.disable_referential_integrity do
      connection.tables.each { |table| connection.drop_table(table, force: :cascade) }
    end
    forget_schema
    ActiveRecord::Schema.define(&block)
  end

  # Tables are dropped and made again under the same names, so forget the
  # columns and the prepared statements that remember the old ones.
  def forget_schema
    connection.schema_cache.clear!
    connection.clear_cache!
    Lethe::Rows.reset!
  end

  # The table bin/rails generate lethe:install creates.
  def ledger_table
    connection.create_table(:lethe_erasures) do |t|
      t.string :subject_type, null: false
      t.string :subject_id, null: false
      t.string :kind, null: false
      t.text :counts, null: false
      t.datetime :created_at, null: false
    end
    forget_schema
  end

  # Defines a model as a constant for this example only.
  def model(name, &body)
    klass = Class.new(ActiveRecord::Base)
    stub_const(name, klass)
    klass.class_eval(&body) if body
    klass
  end

  # Gives a model attachments the way Active Storage reports them,
  # without loading Active Storage.
  def attachments(model, *names)
    reflections = names.to_h { |name| [name, Struct.new(:name).new(name)] }
    model.define_singleton_method(:reflect_on_all_attachments) { reflections.values }
    model.define_singleton_method(:reflect_on_attachment) { |name| reflections[name.to_sym] }
  end

  def check(models, strict: false, definitions: Lethe.definitions.values)
    Lethe.check(definitions: definitions, models: models, strict: strict)
  end

  def result_for(report, key, subject: "User")
    report.results.find { |result| result.key == key && result.subject == subject }
  end
end
