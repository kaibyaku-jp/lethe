# frozen_string_literal: true

# Erases a user with an avatar, a post, an inquiry, a follow and a mute,
# then prints what happened as JSON for the integration specs.
require_relative "../config/environment"
require "json"
require "stringio"

Rails.application.eager_load!
Lethe.load_definitions(Rails.root.join(ENV.fetch("LETHE_DEFINITION", "config/lethe_complete.rb")))

alice = User.create!(nickname: "Alice", email: "alice@example.com")
bob = User.create!(nickname: "Bob", email: "bob@example.com")
[alice, bob].each do |user|
  user.avatar.attach(io: StringIO.new("not really a png"), filename: "#{user.nickname}.png", content_type: "image/png")
end
Post.create!(user: alice, body: "Hello")
Inquiry.create!(user: alice, email: "alice@example.com", message: "Help")
Follow.create!(follower_id: alice.id, following_id: bob.id)
MutedUser.create!(user: bob, muted_user_id: alice.id)
avatar_key = alice.avatar.blob.key

erasure = Lethe.erase!(alice)

puts JSON.generate(
  counts: erasure.counts,
  leftovers: Lethe.leftovers(alice).map(&:to_s),
  user: User.find(alice.id).slice(:nickname, :email, :deleted_at).transform_values(&:present?),
  avatar_file: ActiveStorage::Blob.service.exist?(avatar_key),
  bob_avatar: bob.reload.avatar.attached?,
  ledger: Lethe::Rows.for("lethe_erasures").pluck(:subject_type, :kind)
)
