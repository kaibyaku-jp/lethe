# frozen_string_literal: true

module Lethe
  # One declared policy for one target.
  #
  #   action    :destroy, :scrub, :keep, :ignore or :destroy_attachment
  #   reason    why, in words for people (required for keep and ignore)
  #   retention how long a kept or scrubbed row stays (an ActiveSupport::Duration), or nil
  #   where     a hash of column conditions the policy is limited to, or nil
  #   set       for scrub: the columns to overwrite and their new values;
  #             a Proc is called for each row (with the row, if it takes one)
  #   cascade   delete through Active Record, so that dependent: associations,
  #             callbacks and attachments go too: when erasing, for destroy;
  #             when sweeping, for keep and scrub with a retention
  #   location  "path:line" of the declaration
  Policy = Data.define(:action, :target, :reason, :retention, :where, :set, :cascade, :location) do
    def ignore?
      action == :ignore
    end

    def computed_set?
      set.is_a?(Hash) && set.values.any?(Proc)
    end
  end

  # How the subject's own row goes away.
  SubjectPolicy = Data.define(:destroy, :soft_delete, :scrub, :location)

  # A block to run inside the erasure's transaction: :before or :after.
  Hook = Data.define(:moment, :block, :location)
end
