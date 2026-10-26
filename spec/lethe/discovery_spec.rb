# frozen_string_literal: true

RSpec.describe Lethe::Discovery do
  let(:configuration) { Lethe::Configuration.new }

  def discover(subject, models)
    described_class.new(subject, models: models, connection: connection, configuration: configuration).call
  end

  def vias(references)
    references.to_h { |reference| [reference.key, reference.vias.sort] }
  end

  it "finds foreign keys to the subject's table" do
    schema do
      create_table(:users)
      create_table(:ratings) { |t| t.references :user, foreign_key: true }
      create_table(:follows) { |t| t.references :following, foreign_key: {to_table: :users} }
      create_table(:teams)
      create_table(:players) { |t| t.references :team, foreign_key: true }
    end
    user = model("User")

    expect(vias(discover(user, []))).to eq(
      "follows.following_id" => %i[foreign_key],
      "ratings.user_id" => %i[column_name foreign_key]
    )
  end

  it "finds the subject's has_many, has_one and has_and_belongs_to_many" do
    schema do
      create_table(:users)
      create_table(:ratings) { |t| t.bigint :author_id }
      create_table(:profiles) { |t| t.bigint :owner_id }
      create_table(:groups)
      create_table(:groups_users, id: false) do |t|
        t.bigint :group_id
        t.bigint :member_id
      end
    end
    model("Rating")
    model("Profile")
    model("Group")
    user = model("User") do
      has_many :ratings, foreign_key: :author_id
      has_one :profile, foreign_key: :owner_id
      has_and_belongs_to_many :groups, join_table: :groups_users, foreign_key: :member_id
    end

    expect(vias(discover(user, []))).to eq(
      "groups_users.member_id" => %i[join_table],
      "profiles.owner_id" => %i[association],
      "ratings.author_id" => %i[association]
    )
  end

  it "skips through associations, which point at other tables" do
    schema do
      create_table(:users)
      create_table(:memberships) { |t| t.bigint :member_id }
      create_table(:clubs)
    end
    model("Membership") { belongs_to :club }
    model("Club")
    user = model("User") do
      has_many :memberships, foreign_key: :member_id
      has_many :clubs, through: :memberships
    end

    expect(discover(user, []).map(&:key)).to eq(["memberships.member_id"])
  end

  it "finds belongs_to in other models, with class_name and foreign_key" do
    schema do
      create_table(:users)
      create_table(:questions) { |t| t.bigint :questioner_id }
    end
    user = model("User")
    question = model("Question") { belongs_to :questioner, class_name: "User" }

    expect(vias(discover(user, [question]))).to eq("questions.questioner_id" => %i[association])
  end

  it "treats a polymorphic belongs_to as a guess unless the subject answers it with as:" do
    schema do
      create_table(:users)
      create_table(:comments) { |t| t.references :commentable, polymorphic: true }
      create_table(:reactions) { |t| t.references :target, polymorphic: true }
    end
    comment = model("Comment") { belongs_to :commentable, polymorphic: true }
    reaction = model("Reaction") { belongs_to :target, polymorphic: true }
    user = model("User") { has_many :reactions, as: :target }

    references = discover(user, [comment, reaction])
    expect(vias(references)).to eq(
      "comments.commentable_id" => %i[polymorphic_guess],
      "reactions.target_id" => %i[polymorphic polymorphic_guess]
    )
    expect(references.map(&:certain?)).to eq([false, true])
  end

  it "finds the subject's attachments" do
    schema { create_table(:users) }
    user = model("User")
    attachments(user, :avatar, :photos)

    expect(vias(discover(user, []))).to eq(
      "attachment:avatar" => %i[attachment],
      "attachment:photos" => %i[attachment]
    )
  end

  it "leaves has_one_attached's own associations to the attachments" do
    schema do
      create_table(:users)
      create_table(:active_storage_attachments) do |t|
        t.references :record, polymorphic: true
      end
    end
    user = model("User") { has_one :avatar_attachment, class_name: "ActiveStorage::Attachment", as: :record }

    expect(discover(user, [])).to eq([])
  end

  it "guesses from column names: user_id, *_user_id and configured ones" do
    schema do
      create_table(:users) { |t| t.bigint :referrer_user_id }
      create_table(:muted_users) do |t|
        t.bigint :user_id
        t.bigint :muted_user_id
        t.bigint :username_id
      end
      create_table(:follows) { |t| t.bigint :follower_id }
    end
    user = model("User")
    configuration.guess_columns[user] = %w[follower_id]

    references = discover(user, [])
    expect(vias(references)).to eq(
      "follows.follower_id" => %i[column_name],
      "muted_users.muted_user_id" => %i[column_name],
      "muted_users.user_id" => %i[column_name],
      "users.referrer_user_id" => %i[column_name]
    )
    expect(references.map(&:certain?)).to all(be(false))
  end

  it "leaves out Rails' own tables and configured ones" do
    schema do
      create_table(:users)
      create_table(:audit_logs) { |t| t.bigint :user_id }
      create_table(:ratings) { |t| t.bigint :user_id }
    end
    user = model("User")
    configuration.skip_tables = [:audit_logs]

    expect(discover(user, []).map(&:key)).to eq(["ratings.user_id"])
  end

  it "ignores associations whose class cannot be loaded" do
    schema do
      create_table(:users)
      create_table(:ratings) { |t| t.bigint :owner_id }
    end
    rating = model("Rating") { belongs_to :owner, class_name: "NoSuchClass" }
    user = model("User") { has_many :ghosts }

    expect(discover(user, [rating])).to eq([])
  end

  it "skips abstract models and models without a table" do
    schema { create_table(:users) }
    abstract = Class.new(ActiveRecord::Base) { self.abstract_class = true }
    tableless = model("Draft") { belongs_to :user }
    user = model("User")

    expect(discover(user, [abstract, tableless])).to eq([])
  end

  it "merges what different clues find into one reference, sorted by key" do
    schema do
      create_table(:users)
      create_table(:ratings) { |t| t.references :user, foreign_key: true }
      create_table(:favorites) { |t| t.references :user, foreign_key: true }
    end
    rating = model("Rating") { belongs_to :user }
    user = model("User") { has_many :ratings }

    references = discover(user, [rating])
    expect(references.map(&:key)).to eq(%w[favorites.user_id ratings.user_id])
    expect(references.last.vias.sort).to eq(%i[association column_name foreign_key])
  end
end
