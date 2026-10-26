# frozen_string_literal: true

RSpec.describe "the gem package" do
  let(:spec) { Gem::Specification.load(File.expand_path("../lethe.gemspec", __dir__)) }

  it "ships the rake tasks and both locales" do
    expect(spec.files).to include("lib/lethe/tasks/lethe.rake", "lib/lethe/locales/en.yml", "lib/lethe/locales/ja.yml")
  end

  it "ships the code, license, readme and changelog, and no specs or fixtures" do
    expect(spec.files).to include("lib/lethe.rb", "LICENSE", "README.md", "CHANGELOG.md")
    expect(spec.files.grep(%r{\A(spec|ura|docs|gemfiles)/})).to eq([])
  end

  it "requires MFA to push" do
    expect(spec.metadata["rubygems_mfa_required"]).to eq("true")
  end

  it "has every locale key in both languages" do
    keys = ->(hash, prefix = []) { hash.flat_map { |key, value| value.is_a?(Hash) ? keys.call(value, prefix + [key]) : [(prefix + [key]).join(".")] } }
    en = keys.call(YAML.load_file(File.expand_path("../lib/lethe/locales/en.yml", __dir__))["en"])
    ja = keys.call(YAML.load_file(File.expand_path("../lib/lethe/locales/ja.yml", __dir__))["ja"])

    expect(ja).to match_array(en)
  end
end
