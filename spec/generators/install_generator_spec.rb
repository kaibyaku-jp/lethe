# frozen_string_literal: true

require "tmpdir"
require "generators/lethe/install/install_generator"

RSpec.describe Lethe::Generators::InstallGenerator do
  around do |example|
    Dir.mktmpdir("lethe") do |dir|
      @root = dir
      example.run
    end
  end

  def run_generator
    described_class.start([], destination_root: @root, quiet: true)
  end

  it "writes the migration for lethe_erasures, which creates the table the ledger expects" do
    run_generator

    migration = Dir[File.join(@root, "db/migrate/*_create_lethe_erasures.rb")].sole
    source = File.read(migration)
    expect(source).to include("class CreateLetheErasures < ActiveRecord::Migration[#{ActiveRecord::Migration.current_version}]")

    schema { create_table(:users) }
    load migration
    ActiveRecord::Migration.suppress_messages { CreateLetheErasures.new.migrate(:up) }
    connection.schema_cache.clear!
    Lethe::Rows.reset!
    Lethe::Ledger.record("User", 1, "erase", {"posts.user_id" => {"destroy" => 2}})
    expect(Lethe::Ledger.erased("User").keys).to eq(["1"])
  ensure
    Object.send(:remove_const, :CreateLetheErasures) if defined?(CreateLetheErasures)
  end

  it "writes a config/lethe.rb to start from, and leaves an existing one alone" do
    run_generator
    expect(File.read(File.join(@root, "config/lethe.rb"))).to include('Lethe.define "User"')

    File.write(File.join(@root, "config/lethe.rb"), "# mine\n")
    run_generator
    expect(File.read(File.join(@root, "config/lethe.rb"))).to eq("# mine\n")
  end
end
