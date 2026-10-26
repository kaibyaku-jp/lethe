# frozen_string_literal: true

module Lethe
  # After an erasure, finds what still points at the subject in a way the
  # definition does not allow: rows that should be gone, columns that should
  # have been overwritten, attachments, and the subject's own row.
  #
  # Kept rows are allowed. Values computed by a Proc cannot be compared, so
  # those columns are not checked.
  class Leftovers
    Leftover = Data.define(:key, :problem, :count) do
      def to_s
        "#{key}: #{count} #{problem.to_s.tr("_", " ")}"
      end
    end

    def initialize(subject, id, definition, results, models:)
      @subject = subject
      @id = id
      @definition = definition
      @results = results
      @locator = Locator.new(subject, models: models)
    end

    def call
      references + attachments + subject_row
    end

    private

    def covered
      @results.select { |result| result.status == :covered && result.reference }
    end

    def references
      covered.reject { |result| result.reference.attachment }.flat_map do |result|
        policies = result.policies.reject(&:ignore?)
        next [] if policies.empty?

        location = @locator.locate(policies.first)
        base = @locator.rows(location).where(@locator.conditions(location, nil, @id)).where(declared_type(location, policies))
        found = []

        allowed = policies.select { |policy| %i[keep scrub].include?(policy.action) }
        unless allowed.any? { |policy| policy.where.nil? }
          staying = allowed.map { |policy| base.where(Enums.cast(location.model, policy.where)) }.reduce { |all, scope| all.or(scope) }
          count = base.count - (staying ? staying.count : 0)
          found << Leftover.new(key: result.key, problem: :not_deleted, count: count) if count.positive?
        end

        allowed.select { |policy| policy.action == :scrub }.each do |policy|
          fixed = policy.set.reject { |_, value| value.is_a?(Proc) }
          next if fixed.empty?

          count = base.where(Enums.cast(location.model, policy.where || {})).where.not(Enums.cast(location.model, fixed)).count
          found << Leftover.new(key: result.key, problem: :not_scrubbed, count: count) if count.positive?
        end
        found
      end
    end

    # A "table.column" target names its polymorphic type in where:, which
    # the checker requires; the rows of other types are not this subject's.
    def declared_type(location, policies)
      return {} if location.type_column

      type_column = "#{location.column.delete_suffix("_id")}_type"
      return {} unless @locator.rows(location).column_names.include?(type_column)

      Enums.cast(location.model, policies.first.where).transform_keys(&:to_s).slice(type_column)
    end

    def attachments
      return [] unless defined?(ActiveStorage::Attachment) && ActiveStorage::Attachment.table_exists?

      covered.select { |result| result.reference.attachment }.filter_map do |result|
        count = ActiveStorage::Attachment
          .where(record_type: @subject.polymorphic_name, record_id: @id, name: result.reference.attachment).count
        Leftover.new(key: result.key, problem: :attachment_remains, count: count) if count.positive?
      end
    end

    def subject_row
      policy = @definition.subject_policy
      row = Rows.for(@subject.table_name).where(@subject.primary_key => @id)
      return [] unless policy && row.exists?
      return [Leftover.new(key: "subject", problem: :not_deleted, count: 1)] if policy.destroy

      found = []
      found << Leftover.new(key: "subject", problem: :not_marked_deleted, count: 1) if row.where(policy.soft_delete => nil).exists?
      fixed = policy.scrub.reject { |_, value| value.is_a?(Proc) }
      if fixed.any? && row.where.not(Enums.cast(@subject, fixed)).exists?
        found << Leftover.new(key: "subject", problem: :not_scrubbed, count: 1)
      end
      found
    end
  end
end
