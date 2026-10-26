# frozen_string_literal: true

RSpec.describe Lethe::Formatters do
  let(:root) { File.expand_path("../..", __dir__) }
  let(:models) { sns_schema }

  def render(formatter, report, **options)
    formatter.new(report, root: root, definition_path: File.join(root, "config/lethe.rb"), **options).render
  end

  describe ".for" do
    it "picks a formatter by name, text by default" do
      expect(described_class.for(nil)).to eq(described_class::Text)
      expect(described_class.for("github")).to eq(described_class::GitHub)
      expect(described_class.for("json")).to eq(described_class::JSON)
      expect { described_class.for("xml") }.to raise_error(ArgumentError, /unknown format "xml"/)
    end
  end

  describe described_class::Text do
    it "summarizes and lists what needs attention" do
      models
      sns_definitions
      line = __LINE__ + 1
      Lethe.define("User") { destroy :badges }

      output = render(described_class, check(models))

      expect(output).to eq(<<~TEXT)
        User: 7 references (association 3, attachment 1, column name 4, foreign key 5)

        ✓ 6 have a policy
        ! spec/lethe/formatters_spec.rb:#{line} :badges  User has no association :badges
        ✗ inquiries.user_id                         no policy (found by foreign key, association, column name)

        2 problems, 0 to confirm.
      TEXT
    end

    it "says so when there is nothing to report" do
      models
      sns_definitions(complete: true)

      expect(render(described_class, check(models))).to end_with("✓ 7 have a policy\n\nNo problems.\n")
    end

    it "counts guesses separately unless strict" do
      models
      sns_definitions(complete: true)
      Lethe.definitions["User"].policies.reject! { |policy| policy.target.name == "muted_users.muted_user_id" }

      expect(render(described_class, check(models))).to include("? muted_users.muted_user_id", "0 problems, 1 to confirm.")
      expect(render(described_class, check(models, strict: true))).to include("1 problems, 0 to confirm.")
    end

    it "speaks Japanese" do
      models
      sns_definitions

      output = render(described_class, check(models), locale: :ja)
      expect(output).to include("User: 参照 7 件", "✗ inquiries.user_id  方針がありません（外部キー、関連、列名で見つけました）", "問題 1 件、要確認 0 件。")
    end
  end

  describe described_class::GitHub do
    it "writes an error per problem and a warning per guess, at the declaration when there is one" do
      models
      sns_definitions
      Lethe.definitions["User"].policies.reject! { |policy| policy.target.name == "muted_users.muted_user_id" }
      line = __LINE__ + 1
      Lethe.define("User") { keep :posts }

      lines = render(described_class, check(models)).lines(chomp: true)

      expect(lines).to contain_exactly(
        "::error file=spec/lethe/formatters_spec.rb,line=#{line},title=lethe%3A User %3Aposts::keep needs a reason:",
        "::error file=config/lethe.rb,title=lethe%3A User inquiries.user_id::no policy (found by foreign key, association, column name)",
        "::warning file=config/lethe.rb,title=lethe%3A User muted_users.muted_user_id::guessed from the column name; " \
        "declare a policy, or `ignore` it with a reason if it does not point at User"
      )
    end

    it "escapes what GitHub would read as commands" do
      report = Lethe::Report.new([
        Lethe::Result.new(
          status: :invalid, subject: "User", key: "a,b:c", reference: nil, policies: [],
          message: ["no_table", {table: "x%y\nz"}], location: nil
        )
      ])

      expect(render(described_class, report)).to eq(
        "::error file=config/lethe.rb,title=lethe%3A User a%2Cb%3Ac::there is no table x%25y%0Az\n"
      )
    end

    it "writes nothing when clean" do
      models
      sns_definitions(complete: true)

      expect(render(described_class, check(models))).to eq("")
    end
  end

  describe described_class::JSON do
    it "lists every result" do
      models
      sns_definitions

      data = ::JSON.parse(render(described_class, check(models)))

      expect(data).to include("version" => 1, "clean" => false, "strict" => false)
      expect(data["results"].map { |result| result["key"] }).to eq(%w[
        attachment:avatar follows.follower_id follows.following_id inquiries.user_id
        muted_users.muted_user_id muted_users.user_id posts.user_id subject
      ])
      expect(data["results"].find { |result| result["key"] == "inquiries.user_id" }).to eq(
        "status" => "missing", "subject" => "User", "key" => "inquiries.user_id",
        "vias" => %w[foreign_key association column_name], "actions" => [],
        "message" => "no policy (found by foreign key, association, column name)"
      )
      expect(data["results"].find { |result| result["key"] == "posts.user_id" }).to include(
        "status" => "covered", "actions" => ["scrub"], "file" => "spec/support/sns_schema.rb",
        "line" => File.readlines(File.join(root, "spec/support/sns_schema.rb")).index { |line| line.include?("scrub :posts") } + 1
      )
    end
  end
end
