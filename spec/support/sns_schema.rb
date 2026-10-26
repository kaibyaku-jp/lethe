# frozen_string_literal: true

require "active_support/core_ext/integer/time"

# A small social app: soft-deleted users, posts quoted by others, follows in
# both directions, mutes without a foreign key and support inquiries.
module SnsSchema
  def sns_schema
    schema do
      create_table(:users) do |t|
        t.string :nickname
        t.string :email
        t.datetime :deleted_at
      end
      create_table(:posts) do |t|
        t.references :user, foreign_key: true
        t.text :body
      end
      create_table(:follows) do |t|
        t.references :follower, foreign_key: {to_table: :users}
        t.references :following, foreign_key: {to_table: :users}
      end
      create_table(:muted_users) do |t|
        t.references :user, foreign_key: true
        t.bigint :muted_user_id
      end
      create_table(:inquiries) do |t|
        t.references :user, foreign_key: true
        t.string :email
        t.text :message
      end
    end
    model("Post") { belongs_to :user }
    model("Follow")
    model("MutedUser") { belongs_to :user }
    model("Inquiry") { belongs_to :user }
    model("User") do
      has_many :posts
      has_many :muted_users
      has_many :inquiries, dependent: :destroy
    end
    attachments(User, :avatar)
    [Post, Follow, MutedUser, Inquiry, User]
  end

  # Declares everything but inquiries, the way a soft delete forgets them.
  def sns_definitions(complete: false)
    Lethe.define("User") do
      subject soft_delete: :deleted_at, scrub: {nickname: "Deleted user", email: nil}
      scrub :posts, set: {body: ""}, reason: "Quoted posts keep their row"
      destroy "follows.follower_id", "follows.following_id"
      destroy :muted_users
      keep "muted_users.muted_user_id", reason: "Other people's settings"
      destroy_attachments :avatar
      keep :inquiries, for: 2.years, reason: "Support history" if complete
    end
  end
end

RSpec.configure { |config| config.include SnsSchema }
