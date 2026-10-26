# frozen_string_literal: true

module Lethe
  # One declared policy for one target.
  #
  #   action    :destroy, :scrub, :keep, :ignore or :destroy_attachment
  #   reason    why, in words for people (required for keep and ignore)
  #   retention how long a kept row stays (an ActiveSupport::Duration), or nil
  #   where     a hash of column conditions the policy is limited to, or nil
  #   set       for scrub: the columns to overwrite and their new values
  #   location  "path:line" of the declaration
  Policy = Data.define(:action, :target, :reason, :retention, :where, :set, :location) do
    def ignore?
      action == :ignore
    end
  end

  # How the subject's own row goes away.
  SubjectPolicy = Data.define(:destroy, :soft_delete, :scrub, :location)
end
