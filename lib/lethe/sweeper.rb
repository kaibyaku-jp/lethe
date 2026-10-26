# frozen_string_literal: true

module Lethe
  # Deletes kept rows whose time is up: `keep ..., for: 2.years` keeps a
  # subject's rows for two years after it was first erased, as recorded in
  # lethe_erasures, and this deletes them afterwards.
  class Sweeper
    def initialize(definitions, models:, now: Time.current)
      @definitions = definitions
      @models = models
      @now = now
    end

    # Returns { "User" => { "inquiries.user_id" => 3 } } for what it deleted.
    def call
      @definitions.each_with_object({}) do |definition, swept|
        policies = definition.policies.select { |policy| policy.action == :keep && policy.retention }
        next if policies.empty?

        subject = definition.subject_name.constantize.base_class
        erased = Ledger.erased(subject.name)
        locator = Locator.new(subject, models: @models)
        policies.each do |policy|
          ids = erased.select { |_, at| at <= @now - policy.retention }.keys
          count = sweep(locator, policy, ids, subject)
          (swept[subject.name] ||= {})[policy.target.to_s] = count if count.positive?
        end
      end
    end

    private

    def sweep(locator, policy, ids, subject)
      location = locator.locate(policy)
      rows = locator.rows(location)
      ids.each_slice(500).sum do |slice|
        present = rows.where(locator.conditions(location, policy, slice)).distinct.pluck(location.column)
        present.sum do |id|
          count = rows.where(locator.conditions(location, policy, id)).delete_all
          Ledger.record(subject.name, id, "sweep", {policy.target.to_s => {"sweep" => count}})
          count
        end
      end
    end
  end
end
