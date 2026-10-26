# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"

# Runs the rake tasks in spec/fixtures/sns_app, a small Rails app with real
# Active Storage attachments, in a process of its own.
RSpec.describe "the rake tasks in a Rails app" do
  app = File.expand_path("../fixtures/sns_app", __dir__)
  # The Gemfile in use, so that CI runs the app on each Rails it tests.
  gemfile = File.expand_path(ENV.fetch("BUNDLE_GEMFILE", "Gemfile"), File.expand_path("../..", __dir__))

  around do |example|
    Dir.mktmpdir("lethe") do |dir|
      @tmp = dir
      example.run
    end
  end

  def rake(*tasks, definition: "config/lethe.rb", **env)
    env = {
      "BUNDLE_GEMFILE" => self.class.metadata[:gemfile],
      "LETHE_DEFINITION" => definition,
      "LETHE_EXPORT" => File.join(@tmp, "lethe"),
      "COVERAGE" => "0"
    }.merge(env.transform_keys(&:to_s))
    stdout, stderr, status = Open3.capture3(env, "bundle", "exec", "rake", *tasks, chdir: self.class.metadata[:app])
    [stdout, stderr, status.exitstatus]
  end

  metadata[:app] = app
  metadata[:gemfile] = gemfile

  it "finds what the definitions forgot, and fails" do
    stdout, _, status = rake("lethe:check")

    expect(status).to eq(1)
    expect(stdout).to eq(<<~TEXT)
      User: 8 references (association 3, attachment 1, column name 7, foreign key 3)

      ✓ 5 have a policy
      ? audit_logs.admin_user_id   guessed from the column name; declare a policy, or `ignore` it with a reason if it does not point at User
      ✗ inquiries.user_id          no policy (found by foreign key, association, column name)
      ? muted_users.muted_user_id  guessed from the column name; declare a policy, or `ignore` it with a reason if it does not point at User

      1 problems, 2 to confirm.
    TEXT
  end

  it "writes GitHub annotations" do
    stdout, _, status = rake("lethe:check", FORMAT: "github")

    expect(status).to eq(1)
    expect(stdout.lines.map { |line| line.split("::").values_at(1, 2).join("::") }).to eq([
      "warning file=config/lethe.rb,title=lethe%3A User audit_logs.admin_user_id::guessed from the column name; " \
      "declare a policy, or `ignore` it with a reason if it does not point at User\n",
      "error file=config/lethe.rb,title=lethe%3A User inquiries.user_id::no policy (found by foreign key, association, column name)\n",
      "warning file=config/lethe.rb,title=lethe%3A User muted_users.muted_user_id::guessed from the column name; " \
      "declare a policy, or `ignore` it with a reason if it does not point at User\n"
    ])
  end

  it "passes with complete definitions, then exports, and the export stays up to date" do
    stdout, stderr, status = rake("lethe:check", "lethe:export", definition: "config/lethe_complete.rb", STRICT: "1")

    expect([status, stderr]).to eq([0, ""])
    expect(stdout).to include("✓ 8 have a policy", "No problems.", "lethe: wrote")
    markdown = File.read(File.join(@tmp, "lethe.md"))
    expect(markdown).to include(
      "| The User itself | Kept as deleted (deleted_at), with nickname, email overwritten |  |  |",
      "| Avatar (attachment) | Deleted |  |  |",
      "| Inquiry | Kept | 2 years | Support history |"
    )
    expect(markdown).not_to include("audit_logs")

    _, _, status = rake("lethe:export", definition: "config/lethe_complete.rb", CHECK: "1")
    expect(status).to eq(0)
  end

  it "erases a user with a real attachment, and leaves nothing behind" do
    stdout, stderr, status = Open3.capture3(
      {"BUNDLE_GEMFILE" => self.class.metadata[:gemfile], "COVERAGE" => "0"},
      "bundle", "exec", "ruby", "script/erase.rb", chdir: self.class.metadata[:app]
    )

    expect([status.exitstatus, stderr]).to eq([0, ""])
    result = JSON.parse(stdout)
    expect(result).to include(
      "leftovers" => [],
      "user" => {"nickname" => true, "email" => false, "deleted_at" => true},
      "avatar_file" => false,
      "bob_avatar" => true,
      "ledger" => [%w[User erase]]
    )
    expect(result["counts"]).to include(
      "attachment:avatar" => {"attachment" => 1}, "posts.user_id" => {"scrub" => 1}, "inquiries.user_id" => {"keep" => 0}
    )
  end

  it "sweeps from a rake task" do
    stdout, stderr, status = rake("lethe:sweep", definition: "config/lethe_complete.rb")

    expect([status, stderr, stdout]).to eq([0, "", "lethe: nothing to sweep\n"])
  end

  it "exits 2 when the definitions cannot be loaded" do
    path = File.join(@tmp, "broken.rb")
    File.write(path, "Lethe.define(")

    _, stderr, status = rake("lethe:check", definition: path)

    expect(status).to eq(2)
    expect(stderr).to include("could not load", "SyntaxError")
  end
end
