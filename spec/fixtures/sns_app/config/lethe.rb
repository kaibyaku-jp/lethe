# frozen_string_literal: true

# Users are soft-deleted, so has_many ... dependent: :destroy never runs:
# the inquiries are left out here on purpose, as they so often are.
Lethe.define User do
  subject soft_delete: :deleted_at, scrub: {nickname: "Deleted user", email: nil}

  scrub :posts, set: {body: ""}, reason: "Quoted posts keep their row"
  destroy "follows.follower_id", "follows.following_id"
  destroy :muted_users
  destroy_attachments :avatar
end
