# frozen_string_literal: true

require "active_support/core_ext/integer/time"

RSpec.describe Lethe::Checker do
  before do
    schema do
      create_table(:users) do |t|
        t.string :email
        t.datetime :deleted_at
      end
      create_table(:ratings) { |t| t.references :user, foreign_key: true }
      create_table(:posts) do |t|
        t.references :user, foreign_key: true
        t.text :body
        t.string :status
      end
      create_table(:muted_users) do |t|
        t.bigint :user_id
        t.bigint :muted_user_id
      end
    end
    model("Rating") { belongs_to :user }
    model("Post") { belongs_to :user }
    model("MutedUser")
    model("User") do
      has_many :ratings
      has_many :posts
      has_many :muted_users
      belongs_to :team, optional: true
      has_many :rated_posts, through: :ratings, source: :user
    end
  end

  let(:models) { [Rating, Post, MutedUser, User] }

  def statuses(report)
    report.results.to_h { |result| [result.key, result.status] }
  end

  def message(report, key)
    result_for(report, key).message
  end

  context "when every reference has a policy" do
    before do
      Lethe.define("User") do
        subject soft_delete: :deleted_at, scrub: {email: nil}
        destroy :ratings
        scrub :posts, set: {body: ""}, reason: "quoted by others"
        destroy :muted_users
        keep "muted_users.muted_user_id", reason: "other people's settings"
      end
    end

    it "covers each one and is clean" do
      report = check(models)

      expect(statuses(report)).to eq(
        "muted_users.muted_user_id" => :covered,
        "muted_users.user_id" => :covered,
        "posts.user_id" => :covered,
        "ratings.user_id" => :covered,
        "subject" => :covered
      )
      expect(report).to be_clean
      expect(result_for(report, "posts.user_id").policies.map(&:action)).to eq([:scrub])
    end
  end

  it "reports a certain reference without a policy as missing and a guess as a guess" do
    Lethe.define("User") do
      subject destroy: true
      destroy :ratings, :posts
      destroy :muted_users
    end

    report = check(models)

    expect(statuses(report)).to include("muted_users.muted_user_id" => :guess)
    expect(report).to be_clean
    expect(check(models, strict: true)).not_to be_clean

    Lethe.reset!
    Lethe.define("User") do
      subject destroy: true
      destroy :ratings
    end
    report = check(models)
    expect(statuses(report)).to include(
      "posts.user_id" => :missing, "muted_users.user_id" => :missing, "muted_users.muted_user_id" => :guess
    )
    expect(report.problems.map(&:key)).to eq(%w[muted_users.user_id posts.user_id])
  end

  it "reports a missing subject declaration" do
    Lethe.define("User") { destroy :ratings }

    result = result_for(check(models), "subject")
    expect(result.status).to eq(:missing)
    expect(result.location).to be_nil
  end

  it "marks ignored references as ignored, not covered" do
    Lethe.define("User") do
      subject destroy: true
      ignore "muted_users.muted_user_id", reason: "a guess gone wrong"
    end

    expect(statuses(check(models))).to include("muted_users.muted_user_id" => :ignored)
  end

  it "trusts a valid declaration of a column it did not find" do
    Lethe.define("User") do
      subject destroy: true
      destroy "posts.status"
    end

    result = result_for(check(models), "posts.status")
    expect(result.status).to eq(:covered)
    expect(result.reference.vias).to eq([:declared])
  end

  it "accepts different policies for different rows" do
    Lethe.define("User") do
      subject destroy: true
      scrub :posts, where: {status: "answered"}, set: {body: ""}
      destroy :posts, where: {status: %w[draft]}
    end

    expect(result_for(check(models), "posts.user_id").status).to eq(:covered)
  end

  describe "declarations that are wrong" do
    {
      "an unknown association" => [-> { destroy :teams_of_mine }, ":teams_of_mine", "no_association"],
      "a through association" => [-> { destroy :rated_posts }, ":rated_posts", "through_association"],
      "a belongs_to" => [-> { destroy :team }, ":team", "belongs_to_association"],
      "an unknown table" => [-> { destroy "comments.user_id" }, "comments.user_id", "no_table"],
      "an unknown column" => [-> { destroy "posts.author_id" }, "posts.author_id", "no_column"],
      "an unknown attachment" => [-> { destroy_attachments :avatar }, "attachment :avatar", "no_attachment"],
      "keep without a reason" => [-> { keep :ratings }, ":ratings", "reason_required"],
      "ignore with a blank reason" => [-> { ignore :ratings, reason: "  " }, ":ratings", "reason_required"],
      "a reason that is not a string" => [-> { destroy :ratings, reason: :spam }, ":ratings", "reason_not_string"],
      "scrub with nothing to set" => [-> { scrub :posts, set: {} }, ":posts", "set_required"],
      "scrub of an unknown column" => [-> { scrub :posts, set: {title: nil} }, ":posts", "unknown_column"],
      "where that is not a hash" => [-> { destroy :posts, where: "status = 'x'" }, ":posts", "where_not_hash"],
      "where on an unknown column" => [-> { destroy :posts, where: {kind: "x"} }, ":posts", "unknown_column"],
      "for that is not a duration" => [-> { keep :ratings, reason: "x", for: 7 }, ":ratings", "retention_not_duration"]
    }.each do |description, (declaration, key, message_key)|
      it "reports #{description}" do
        Lethe.define("User") do
          subject destroy: true
          instance_exec(&declaration)
        end

        result = result_for(check(models), key)
        expect(result.status).to eq(:invalid)
        expect(result.message.first).to eq(message_key)
        expect(result.location).to match(/checker_spec\.rb:\d+\z/)
      end
    end

    it "reports an association whose class cannot be loaded" do
      User.has_many :ghosts
      Lethe.define("User") do
        subject destroy: true
        destroy :ghosts
      end

      expect(message(check(models), ":ghosts").first).to eq("association_class_missing")
    end

    it "reports two policies that disagree about the same rows" do
      Lethe.define("User") do
        subject destroy: true
        destroy :ratings
        keep :ratings, reason: "changed my mind"
      end

      report = check(models)
      invalid = report.results.select { |result| result.status == :invalid }
      expect(invalid.map { |result| result.message.first }).to eq(["contradiction"])
      expect(invalid.sole.message.last).to include(key: "ratings.user_id")
      expect(result_for(report, "ratings.user_id").status).to eq(:covered)
    end

    {
      "both destroy and soft_delete" => [{destroy: true, soft_delete: :deleted_at}, "subject_both"],
      "neither destroy nor soft_delete" => [{}, "subject_neither"],
      "an unknown soft_delete column" => [{soft_delete: :removed_at}, "unknown_column"],
      "scrub that is not a hash" => [{destroy: true, scrub: [:email]}, "subject_scrub_not_hash"],
      "scrub of an unknown column" => [{destroy: true, scrub: {phone: nil}}, "unknown_column"]
    }.each do |description, (options, message_key)|
      it "reports a subject declaration with #{description}" do
        Lethe.define("User") { subject(**options) }

        result = result_for(check(models), "subject")
        expect(result.status).to eq(:invalid)
        expect(result.message.first).to eq(message_key)
      end
    end

    it "reports a subject that is not a model" do
      Lethe.define("Nobody") { destroy :ratings }

      result = check(models).results.sole
      expect(result).to have_attributes(status: :invalid, key: "Nobody", subject: "Nobody")
      expect(result.message.first).to eq("subject_not_a_model")
    end
  end

  it "gives every discovered reference exactly one result" do
    Lethe.define("User") { subject destroy: true }
    references = Lethe::Discovery.new(
      User, models: models, connection: connection, configuration: Lethe.configuration
    ).call

    results = check(models).results.select(&:reference)
    expect(results.map(&:key)).to match_array(references.map(&:key))
  end
end
