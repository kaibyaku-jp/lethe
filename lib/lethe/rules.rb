# frozen_string_literal: true

module Lethe
  # The rules a declared policy must follow once its target is known to
  # exist. Each rule returns the problems it finds, as :invalid Results.
  # They exist so that a definition that would erase the wrong rows, or
  # fail halfway, never passes the check.
  class Rules
    RULES = %i[
      reason_given reason_is_text
      scrub_sets_columns where_names_columns
      retention_only_where_rows_stay cascade_on_kept_rows_needs_retention retention_is_duration
      enum_values_exist polymorphic_type_given cascade_has_model computed_values_have_primary_key
    ].freeze

    # schema answers column_names(table), model_for_table(table) and
    # primary_key(table); invalid builds the :invalid Result for a policy.
    def initialize(subject, schema, &invalid)
      @subject = subject
      @schema = schema
      @invalid = invalid
    end

    def call(policy, key)
      table = key.start_with?("attachment:") ? nil : key.split(".", 2).first
      RULES.flat_map { |rule| Array(send(rule, policy, key, table)) }
    end

    private

    # keep and ignore are decisions to leave data in place; the export and
    # anyone auditing it need to know why.
    def reason_given(policy, _key, _table)
      return unless %i[keep ignore].include?(policy.action) && blank?(policy.reason)

      problem(policy, "reason_required", action: policy.action)
    end

    def reason_is_text(policy, _key, _table)
      problem(policy, "reason_not_string") unless policy.reason.nil? || policy.reason.is_a?(String)
    end

    def scrub_sets_columns(policy, _key, table)
      return unless policy.action == :scrub
      return problem(policy, "set_required") if !policy.set.is_a?(Hash) || policy.set.empty?

      unknown_columns(policy, table, policy.set.keys, "set")
    end

    def where_names_columns(policy, _key, table)
      return if policy.where.nil?
      return problem(policy, "where_not_hash") if !policy.where.is_a?(Hash) || policy.where.empty?

      unknown_columns(policy, table, policy.where.keys, "where")
    end

    # Only rows that stay can stay for a while.
    def retention_only_where_rows_stay(policy, _key, _table)
      return unless policy.retention && !staying?(policy)

      problem(policy, "retention_not_allowed", action: policy.action)
    end

    def retention_is_duration(policy, _key, _table)
      return if policy.retention.nil? || policy.retention.is_a?(ActiveSupport::Duration)

      problem(policy, "retention_not_duration")
    end

    # On keep and scrub, cascade only changes how lethe:sweep deletes.
    def cascade_on_kept_rows_needs_retention(policy, _key, _table)
      return unless policy.cascade && staying?(policy) && policy.retention.nil?

      problem(policy, "cascade_without_retention", action: policy.action)
    end

    # Rows are reached without the application's model, so an enum name the
    # enum does not have would silently match nothing.
    def enum_values_exist(policy, _key, table)
      return unless table

      model = @schema.model_for_table(table)
      {"where" => policy.where, "set" => (policy.action == :scrub) ? policy.set : nil}.flat_map do |option, hash|
        Enums.unknown(model, hash).map do |column, value|
          problem(policy, "unknown_enum_value", option: option, table: table, column: column, value: value.inspect)
        end
      end
    end

    # A "table.column" for a polymorphic *_id must say which type it means,
    # or erasing User 5 would also erase what belongs to Post 5.
    def polymorphic_type_given(policy, key, table)
      return unless table && policy.target.kind == :column

      column = key.split(".", 2).last
      return unless column.end_with?("_id")

      type_column = "#{column.delete_suffix("_id")}_type"
      return unless @schema.column_names(table).include?(type_column)
      return if policy.where.is_a?(Hash) && policy.where.keys.map(&:to_s).include?(type_column)

      problem(policy, "polymorphic_type_required", key: key, type_column: type_column, subject_type: @subject.polymorphic_name)
    end

    def cascade_has_model(policy, _key, table)
      problem(policy, "cascade_needs_model", table: table) if table && policy.cascade && !@schema.model_for_table(table)
    end

    # A Proc in set: is evaluated row by row, which needs a key to update by.
    def computed_values_have_primary_key(policy, _key, table)
      return unless table && policy.action == :scrub && policy.computed_set?

      problem(policy, "computed_set_needs_primary_key", table: table) unless @schema.primary_key(table)
    end

    def unknown_columns(policy, table, names, option)
      return [] unless table

      (names.map(&:to_s) - @schema.column_names(table)).map do |column|
        problem(policy, "unknown_column", option: option, table: table, column: column)
      end
    end

    def staying?(policy)
      %i[keep scrub].include?(policy.action)
    end

    def problem(policy, message_key, **values)
      @invalid.call(policy, message_key, **values)
    end

    def blank?(value)
      value.nil? || (value.is_a?(String) && value.strip.empty?)
    end
  end
end
