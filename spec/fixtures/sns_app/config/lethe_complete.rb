# frozen_string_literal: true

Lethe.define User do
  subject soft_delete: :deleted_at, scrub: {nickname: "Deleted user", email: nil}

  scrub :posts, set: {body: ""}, reason: "Quoted posts keep their row"
  destroy "follows.follower_id", "follows.following_id"
  destroy :muted_users
  keep "muted_users.muted_user_id", reason: "Other people's settings"
  keep :inquiries, for: 2.years, reason: "Support history"
  ignore "audit_logs.admin_user_id", reason: "Points at AdminUser"
  destroy_attachments :avatar
end
