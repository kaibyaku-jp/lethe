# frozen_string_literal: true

require "stringio"
require "tmpdir"

RSpec.describe Lethe::Runner do
  around do |example|
    Dir.mktmpdir("lethe") do |dir|
      @root = dir
      example.run
    end
  end

  let(:models) { sns_schema }
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  def definitions(source)
    path = File.join(@root, "config/lethe.rb")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source)
  end

  def complete_definitions
    definitions(<<~RUBY)
      Lethe.define "User" do
        subject soft_delete: :deleted_at
        scrub :posts, set: { body: "" }
        destroy "follows.follower_id", "follows.following_id", :muted_users, :inquiries
        keep "muted_users.muted_user_id", reason: "Other people's settings"
        destroy_attachments :avatar
      end
    RUBY
  end

  def runner(env = {})
    described_class.new(root: @root, env: env, out: out, err: err, models: models)
  end

  describe "#check" do
    it "returns 0 and prints the report when clean" do
      complete_definitions

      expect(runner.check).to eq(0)
      expect(out.string).to include("✓ 7 have a policy", "No problems.")
    end

    it "returns 1 when there are problems" do
      definitions(%(Lethe.define("User") { subject destroy: true }))

      expect(runner.check).to eq(1)
      expect(out.string).to include("✗ posts.user_id")
    end

    it "returns 1 for guesses only when strict" do
      definitions(<<~RUBY)
        Lethe.define "User" do
          subject destroy: true
          destroy :posts, :muted_users, :inquiries, "follows.follower_id", "follows.following_id"
          destroy_attachments :avatar
        end
      RUBY

      expect(runner.check).to eq(0)
      expect(runner("STRICT" => "1").check).to eq(1)
    end

    it "prints the format asked for" do
      complete_definitions

      expect(runner("FORMAT" => "json").check).to eq(0)
      expect(JSON.parse(out.string)["clean"]).to be(true)
    end

    it "returns 2 for an unknown format" do
      complete_definitions

      expect(runner("FORMAT" => "xml").check).to eq(2)
      expect(err.string).to include("unknown format")
    end

    it "returns 2 when the definitions file is missing" do
      expect(runner.check).to eq(2)
      expect(err.string).to include("config/lethe.rb not found")
    end

    it "returns 2 when the definitions file cannot be loaded" do
      definitions(%(Lethe.define("User") { destroy 42 }))

      expect(runner.check).to eq(2)
      expect(err.string).to include("could not load config/lethe.rb", "ArgumentError")
    end

    it "returns 2 for a syntax error" do
      definitions("Lethe.define(")

      expect(runner.check).to eq(2)
      expect(err.string).to include("SyntaxError")
    end

    it "returns 2 for a locale it does not know" do
      complete_definitions

      expect(runner("LOCALE" => "xx").check).to eq(2)
      expect(err.string).to include("LOCALE=xx")
    end

    it "uses the configured definitions path" do
      Lethe.configure { |config| config.definition_path = "lethe/policies.rb" }
      FileUtils.mkdir_p(File.join(@root, "lethe"))
      File.write(File.join(@root, "lethe/policies.rb"), %(Lethe.define("User") { subject destroy: true }))

      expect(runner.check).to eq(1)
    end
  end

  describe "#sweep" do
    it "returns 2 without the ledger table" do
      complete_definitions

      expect(runner.sweep).to eq(2)
      expect(err.string).to include("lethe_erasures")
    end

    it "says when there is nothing to sweep" do
      complete_definitions
      models
      ledger_table

      expect(runner.sweep).to eq(0)
      expect(out.string).to eq("lethe: nothing to sweep\n")
    end

    it "returns 2 when the definitions cannot be loaded" do
      definitions("Lethe.define(")

      expect(runner.sweep).to eq(2)
      expect(err.string).to include("SyntaxError")
    end

    it "returns 2 for a locale it does not know" do
      expect(runner("LOCALE" => "xx").sweep).to eq(2)
    end
  end

  describe "#export" do
    let(:markdown) { File.join(@root, "docs/lethe.md") }
    let(:json) { File.join(@root, "docs/lethe.json") }

    it "writes Markdown and JSON" do
      complete_definitions

      expect(runner.export).to eq(0)
      expect(File.read(markdown)).to include("# What happens when a User leaves")
      expect(JSON.parse(File.read(json))["subjects"].sole["subject"]).to eq("User")
      expect(out.string).to eq("lethe: wrote docs/lethe.md\nlethe: wrote docs/lethe.json\n")
    end

    it "writes in the language asked for" do
      complete_definitions

      runner("LOCALE" => "ja").export
      expect(File.read(markdown)).to include("# User が退会するとどうなるか")
    end

    it "writes nothing while there are problems" do
      definitions(%(Lethe.define("User") { subject destroy: true }))

      expect(runner.export).to eq(1)
      expect(File).not_to exist(markdown)
      expect(err.string).to include("✗ posts.user_id")
    end

    it "returns 2 when it cannot check" do
      expect(runner.export).to eq(2)
    end

    it "with CHECK=1, compares instead of writing" do
      complete_definitions

      expect(runner("CHECK" => "1").export).to eq(1)
      expect(err.string).to include("docs/lethe.md, docs/lethe.json out of date")
      expect(File).not_to exist(markdown)

      runner.export
      expect(runner("CHECK" => "1").export).to eq(0)
      expect(out.string).to end_with("up to date\n")

      File.write(json, "{}")
      expect(runner("CHECK" => "true").export).to eq(1)
      expect(err.string).to end_with("docs/lethe.json out of date; run bin/rails lethe:export\n")
    end

    it "uses the configured export path" do
      complete_definitions
      Lethe.configure { |config| config.export_path = "doc/privacy/deletion" }

      runner.export
      expect(File).to exist(File.join(@root, "doc/privacy/deletion.md"))
    end
  end
end
