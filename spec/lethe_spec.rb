# frozen_string_literal: true

require "tmpdir"

RSpec.describe Lethe do
  let(:models) { sns_schema }

  describe ".check!" do
    it "returns the report when clean" do
      models
      sns_definitions(complete: true)

      expect(described_class.check!(models: models)).to be_clean
    end

    it "raises with the text report when not" do
      models
      sns_definitions

      expect { described_class.check!(models: models) }.to raise_error(Lethe::Unclean, /✗ inquiries\.user_id/) do |error|
        expect(error.report).not_to be_clean
      end
    end
  end

  describe ".check" do
    it "uses every loaded model by default" do
      models
      sns_definitions(complete: true)

      expect(described_class.check.results.map(&:key)).to include("inquiries.user_id")
    end

    it "checks each subject" do
      models
      sns_definitions(complete: true)
      described_class.define("Post") { subject destroy: true }

      expect(described_class.check(models: models).subjects).to eq(%w[User Post])
    end
  end

  describe ".load_definitions" do
    it "forgets earlier definitions, then loads the file" do
      described_class.define("Post") { subject destroy: true }
      Dir.mktmpdir do |dir|
        path = File.join(dir, "lethe.rb")
        File.write(path, %(Lethe.define("User") { subject destroy: true }))

        expect(described_class.load_definitions(path).keys).to eq(["User"])
      end
    end

    it "raises when the file is missing" do
      expect { described_class.load_definitions("/nonexistent/lethe.rb") }.to raise_error(Lethe::DefinitionError, /not found/)
    end
  end

  describe ".configure" do
    it "keys guess_columns by class or name" do
      user = model("User")
      described_class.configure { |config| config.guess_columns[user] = [:follower_id] }

      expect(described_class.configuration.guess_columns["User"]).to eq(["follower_id"])
      expect(described_class.configuration.guess_columns_for("User")).to eq(["follower_id"])
      expect(described_class.configuration.guess_columns_for("Post")).to eq([])
    end
  end

  it "has a version RubyGems accepts" do
    expect(Gem::Version.correct?(Lethe::VERSION)).to be(true)
  end
end
