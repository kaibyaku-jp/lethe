# frozen_string_literal: true

require "active_support/core_ext/integer/time"
require "active_support/testing/time_helpers"

RSpec.describe "Lethe.erase!" do
  include ActiveSupport::Testing::TimeHelpers

  before do
    schema do
      create_table(:users) do |t|
        t.string :nickname
        t.string :email
        t.string :screen_name
        t.datetime :deleted_at
      end
      create_table(:posts) do |t|
        t.references :user, foreign_key: true
        t.text :body
        t.string :status
        t.datetime :deleted_at
      end
      create_table(:comments) do |t|
        t.references :post, foreign_key: true
        t.references :user, foreign_key: true
        t.text :body
      end
      create_table(:ratings) { |t| t.references :target, polymorphic: true }
      create_table(:follows) do |t|
        t.bigint :follower_id
        t.bigint :following_id
      end
      create_table(:inquiries) do |t|
        t.references :user, foreign_key: true
        t.text :message
      end
    end
    model("Comment") do
      belongs_to :post
      belongs_to :user
    end
    model("Post") do
      belongs_to :user
      has_many :comments, dependent: :destroy
    end
    model("Rating") { belongs_to :target, polymorphic: true }
    model("Follow")
    model("Inquiry")
    model("User") do
      has_many :posts
      has_many :comments
      has_many :ratings, as: :target
      has_many :inquiries
      default_scope { where(deleted_at: nil) }
    end
  end

  let(:models) { [Comment, Post, Rating, Follow, Inquiry, User] }
  let!(:alice) { User.create!(nickname: "Alice", email: "alice@example.com", screen_name: "alice") }
  let!(:bob) { User.create!(nickname: "Bob", email: "bob@example.com", screen_name: "bob") }

  def define(&extra)
    Lethe.define("User") do
      subject soft_delete: :deleted_at,
        scrub: {nickname: "Deleted user", email: nil, screen_name: ->(user) { "deleted_#{user.id}" }}
      destroy :comments
      destroy :posts, where: {status: "draft"}, cascade: true
      scrub :posts, where: {status: "published"}, set: {body: "", deleted_at: -> { Time.current }}
      destroy :ratings
      destroy "follows.follower_id", "follows.following_id"
      keep :inquiries, reason: "Support history"
      instance_exec(&extra) if extra
    end
  end

  def seed(user, other)
    draft = user.posts.create!(body: "draft", status: "draft")
    published = user.posts.create!(body: "hello", status: "published")
    Comment.create!(post: draft, user: other, body: "on a draft")
    Comment.create!(post: published, user: user, body: "my own comment")
    Comment.create!(post: published, user: other, body: "a reply")
    Rating.create!(target: user)
    Follow.create!(follower_id: user.id, following_id: other.id)
    Follow.create!(follower_id: other.id, following_id: user.id)
    Inquiry.create!(user_id: user.id, message: "Help")
  end

  def snapshot(user)
    {
      posts: Post.where(user_id: user.id).order(:id).pluck(:body, :status, :deleted_at),
      comments: Comment.where(user_id: user.id).count,
      ratings: Rating.where(target: user).count,
      inquiries: Inquiry.where(user_id: user.id).count,
      user: User.unscoped.where(id: user.id).pluck(:nickname, :email, :screen_name, :deleted_at)
    }
  end

  before do
    seed(alice, bob)
    seed(bob, alice)
  end

  it "erases what the definition says, and leaves nothing else behind" do
    define

    erasure = Lethe.erase!(alice, models: models)

    expect(erasure.counts).to include(
      # One on her own post, two on Bob's; she and Bob follow each other twice.
      "comments.user_id" => {"destroy" => 3},
      "follows.follower_id" => {"destroy" => 2},
      "follows.following_id" => {"destroy" => 2},
      "posts.user_id" => {"destroy" => 1, "scrub" => 1},
      "ratings.target_id" => {"destroy" => 1},
      "inquiries.user_id" => {"keep" => 0},
      "subject" => {"subject" => 1}
    )
    expect(Post.where(user_id: alice.id).pluck(:body, :status)).to eq([["", "published"]])
    expect(Post.where(user_id: alice.id).pick(:deleted_at)).to be_present
    expect(Inquiry.where(user_id: alice.id).count).to eq(1)
    expect(User.unscoped.find(alice.id)).to have_attributes(
      nickname: "Deleted user", email: nil, screen_name: "deleted_#{alice.id}", deleted_at: be_present
    )
    expect(Lethe.leftovers(alice, models: models)).to eq([])
  end

  it "deletes the children of a cascaded destroy through Active Record" do
    define
    draft = Post.find_by(user_id: alice.id, status: "draft")

    Lethe.erase!(alice, models: models)

    expect(Comment.where(post_id: draft.id)).to be_empty
  end

  it "leaves other people's data alone" do
    define
    before = snapshot(bob)
    bobs_comments_on_alices_posts = Comment.where(user_id: bob.id).count

    Lethe.erase!(alice, models: models)

    expect(snapshot(bob).except(:comments)).to eq(before.except(:comments))
    # Bob's comment on Alice's draft goes with the draft; the rest stay.
    expect(Comment.where(user_id: bob.id).count).to eq(bobs_comments_on_alices_posts - 1)
    expect(Follow.where(follower_id: bob.id, following_id: alice.id)).to be_empty
  end

  it "never confuses a polymorphic id with another type's" do
    connection.create_table(:widgets)
    connection.schema_cache.clear!
    widget_class = Class.new(ActiveRecord::Base) { self.table_name = "widgets" }
    stub_const("Widget", widget_class)
    widget = Widget.create!(id: alice.id)
    Rating.create!(target: widget)
    define

    Lethe.erase!(alice, models: models)

    expect(Rating.where(target_type: "Widget", target_id: alice.id).count).to eq(1)
  end

  it "plans the same steps it carries out, and changes nothing while planning" do
    define
    before = snapshot(alice)

    plan = Lethe.plan(alice, models: models)

    expect(snapshot(alice)).to eq(before)
    # Comments have a foreign key to posts, so they go first.
    expect(plan.map(&:key).index("comments.user_id")).to be < plan.map(&:key).index("posts.user_id")
    expect(plan.map(&:key).last).to eq("subject")
    expect(plan.to_s).to include("destroy (cascade)", "scrub body, deleted_at", "keep")

    erasure = Lethe.erase!(alice, models: models)
    planned = plan.reject { |step| step.kind == :keep }.group_by(&:key)
      .transform_values { |steps| steps.to_h { |step| [step.kind.to_s, step.count] } }
    expect(erasure.counts.reject { |_, count| count.key?("keep") }).to eq(planned)
  end

  it "refuses, and changes nothing, while the definition has problems" do
    Lethe.define("User") do
      subject soft_delete: :deleted_at
      destroy :comments
    end
    before = snapshot(alice)

    expect { Lethe.erase!(alice, models: models) }.to raise_error(Lethe::Unclean, /posts\.user_id/)
    expect(snapshot(alice)).to eq(before)
  end

  it "rolls everything back when a step fails" do
    define { after_erase { |_| raise "the mail server is down" } }
    before = snapshot(alice)

    expect { Lethe.erase!(alice, models: models) }.to raise_error(RuntimeError, "the mail server is down")
    expect(snapshot(alice)).to eq(before)
  end

  it "runs the hooks inside the transaction, before and after the steps" do
    seen = []
    define do
      before_erase { |user| seen << [:before, user.id, Comment.where(user_id: user.id).count] }
      after_erase { |user| seen << [:after, user.id, Comment.where(user_id: user.id).count] }
    end

    Lethe.erase!(alice, models: models)

    expect(seen).to eq([[:before, alice.id, 3], [:after, alice.id, 0]])
  end

  it "can run twice, keeping the time of the first erasure" do
    define
    travel_to(Time.utc(2026, 1, 1)) { Lethe.erase!(alice, models: models) }

    erasure = travel_to(Time.utc(2026, 2, 1)) { Lethe.erase!(alice, models: models) }

    expect(erasure.counts.values.sum { |count| count.fetch("destroy", 0) }).to eq(0)
    expect(User.unscoped.find(alice.id).deleted_at).to eq(Time.utc(2026, 1, 1))
    expect(Lethe.leftovers(alice, models: models)).to eq([])
  end

  it "deletes the subject's row with destroy: true" do
    Lethe.define("User") do
      subject destroy: true
      destroy :comments, :ratings, :inquiries
      destroy :posts, cascade: true
      destroy "follows.follower_id", "follows.following_id"
    end

    Lethe.erase!(alice, models: models)

    expect(User.unscoped.where(id: alice.id)).to be_empty
    expect(Lethe.leftovers(User, alice.id, models: models)).to eq([])
  end

  it "reports what an erasure missed" do
    define
    Lethe.erase!(alice, models: models)
    Comment.create!(post: Post.find_by(user_id: bob.id), user_id: alice.id, body: "written later")
    Post.where(user_id: alice.id).update_all(body: "restored")
    User.unscoped.where(id: alice.id).update_all(deleted_at: nil, email: "alice@example.com")

    expect(Lethe.leftovers(alice, models: models).map(&:to_s)).to eq([
      "comments.user_id: 1 not deleted",
      "posts.user_id: 1 not scrubbed",
      "subject: 1 not marked deleted",
      "subject: 1 not scrubbed"
    ])
  end

  it "tells the application, with ids and counts only" do
    define
    events = []
    callback = ->(*, payload) { events << payload }

    ActiveSupport::Notifications.subscribed(callback, "erase.lethe") { Lethe.erase!(alice, models: models) }

    expect(events.sole).to include(subject: "User", id: alice.id)
    expect(events.sole.to_s).not_to include("alice@example.com", "hello")
  end

  it "refuses a definition it has no subject for" do
    expect { Lethe.erase!(alice, models: models) }.to raise_error(Lethe::Error, /no Lethe.define for User/)
  end

  it "refuses foreign keys it cannot order" do
    connection.add_reference(:posts, :pinned_comment, foreign_key: {to_table: :comments})
    connection.schema_cache.clear!
    Lethe::Rows.reset!
    define

    expect { Lethe.plan(alice, models: models) }.to raise_error(Lethe::Error, /cycle/)
  end

  describe "the ledger and keep for:" do
    def define_with_retention
      Lethe.define("User") do
        subject soft_delete: :deleted_at
        destroy :comments, :ratings
        destroy :posts, cascade: true
        destroy "follows.follower_id", "follows.following_id"
        keep :inquiries, for: 2.years, reason: "Support history"
      end
    end

    it "needs the ledger table to keep rows for a while" do
      define_with_retention

      expect { Lethe.erase!(alice, models: models) }.to raise_error(Lethe::Error, /lethe:install/)
      expect(Comment.where(user_id: alice.id).count).to eq(3)
    end

    it "records each erasure without anything personal" do
      ledger_table
      define

      Lethe.erase!(alice, models: models)

      row = Lethe::Rows.for("lethe_erasures").sole
      expect(row).to have_attributes(subject_type: "User", subject_id: alice.id.to_s, kind: "erase")
      expect(JSON.parse(row.counts)["comments.user_id"]).to eq("destroy" => 3)
      expect(row.attributes.values.join(" ")).not_to include("alice", "Alice", "hello")
    end

    it "sweeps kept rows once their time is up, and only those" do
      ledger_table
      define_with_retention
      travel_to(Time.utc(2026, 1, 1)) { Lethe.erase!(alice, models: models) }

      expect(Lethe.sweep!(models: models, now: Time.utc(2027, 1, 1))).to eq({})
      expect(Inquiry.where(user_id: alice.id).count).to eq(1)

      swept = Lethe.sweep!(models: models, now: Time.utc(2028, 1, 2))
      expect(swept).to eq("User" => {":inquiries" => 1})
      expect(Inquiry.where(user_id: alice.id)).to be_empty
      expect(Inquiry.where(user_id: bob.id).count).to eq(1)
      expect(Lethe::Rows.for("lethe_erasures").where(kind: "sweep").pluck(:subject_id)).to eq([alice.id.to_s])

      expect(Lethe.sweep!(models: models, now: Time.utc(2029, 1, 1))).to eq({})
    end

    it "needs the ledger table to sweep" do
      expect { Lethe.sweep!(models: models) }.to raise_error(Lethe::Error, /lethe_erasures/)
    end
  end
end
