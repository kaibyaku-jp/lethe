# frozen_string_literal: true

# A fresh schema for each example, on SQLite in memory by default.
# Set DATABASE_URL to run the same specs on MySQL or PostgreSQL.
module DatabaseHelpers
  def self.connect
    ActiveRecord::Base.establish_connection(ENV.fetch("DATABASE_URL", "sqlite3::memory:"))
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
    connection.schema_cache.clear!
    Lethe::Rows.reset!
    ActiveRecord::Schema.define(&block)
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
    connection.schema_cache.clear!
    Lethe::Rows.reset!
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
