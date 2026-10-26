# frozen_string_literal: true

module Lethe
  # Compares one definition with what Discovery finds, and returns a Result
  # for every reference and for every declaration that is wrong.
  class Checker
    def initialize(definition, models:, connection:, configuration:)
      @definition = definition
      @models = models
      @connection = connection
      @configuration = configuration
    end

    def call
      @subject = resolve_subject
      return [invalid(nil, "subject_not_a_model", location: first_location, subject: subject_name)] unless @subject

      discovery = Discovery.new(@subject, models: models, connection: @connection, configuration: @configuration)
      @tables = discovery.tables
      references = discovery.call

      results = []
      by_key = Hash.new { |hash, key| hash[key] = [] }
      @definition.policies.each do |policy|
        key, error = resolve(policy)
        if error
          results << error
        else
          problems = validate(policy, key)
          results.concat(problems)
          by_key[key] << policy if problems.empty?
        end
      end
      results.concat(contradictions(by_key))

      references.each do |reference|
        results << result_for(reference, by_key.delete(reference.key) || [])
      end
      # Declared and valid, but not something Discovery found: trust the declaration.
      by_key.each do |key, policies|
        table, column = key.split(".", 2)
        results << result_for(Reference.column(table, column, :declared), policies)
      end

      results << subject_result
      results.concat(blocked_by_foreign_keys(results))
      results
    end

    private

    def subject_name
      @definition.subject_name
    end

    def models
      @models || Lethe.application_models
    end

    def resolve_subject
      model = subject_name.safe_constantize
      (model.is_a?(Class) && model < ActiveRecord::Base && !model.abstract_class?) ? model : nil
    end

    def first_location
      @definition.policies.first&.location || @definition.subject_policy&.location
    end

    # Returns [key, nil], or [nil, an :invalid Result].
    def resolve(policy)
      target = policy.target
      case target.kind
      when :association then resolve_association(policy)
      when :attachment then resolve_attachment(policy)
      else resolve_column(policy, target.table, target.column)
      end
    end

    def resolve_association(policy)
      name = policy.target.name
      reflection = @subject.reflect_on_association(name)
      return [nil, invalid(policy, "no_association", name: name)] unless reflection
      return [nil, invalid(policy, "through_association", name: name)] if reflection.through_reflection?

      case reflection.macro
      when :has_many, :has_one
        table = begin
          reflection.klass.table_name
        rescue NameError, ArgumentError
          return [nil, invalid(policy, "association_class_missing", name: name)]
        end
        resolve_column(policy, table, reflection.foreign_key.to_s)
      when :has_and_belongs_to_many
        resolve_column(policy, reflection.join_table.to_s, reflection.foreign_key.to_s)
      else
        [nil, invalid(policy, "belongs_to_association", name: name)]
      end
    end

    def resolve_attachment(policy)
      name = policy.target.name
      found = @subject.respond_to?(:reflect_on_attachment) && @subject.reflect_on_attachment(name)
      found ? ["attachment:#{name}", nil] : [nil, invalid(policy, "no_attachment", name: name)]
    end

    def resolve_column(policy, table, column)
      return [nil, invalid(policy, "no_table", table: table)] unless @tables.include?(table)
      return [nil, invalid(policy, "no_column", table: table, column: column)] unless column_names(table).include?(column)

      ["#{table}.#{column}", nil]
    end

    def column_names(table)
      @column_names ||= {}
      @column_names[table] ||= @connection.columns(table).map(&:name)
    end

    # Problems with a policy whose target exists.
    def validate(policy, key)
      problems = []
      table = key.start_with?("attachment:") ? nil : key.split(".", 2).first

      if %i[keep ignore].include?(policy.action) && blank?(policy.reason)
        problems << invalid(policy, "reason_required", action: policy.action)
      end
      problems << invalid(policy, "reason_not_string") unless policy.reason.nil? || policy.reason.is_a?(String)

      if policy.action == :scrub
        if !policy.set.is_a?(Hash) || policy.set.empty?
          problems << invalid(policy, "set_required")
        elsif table
          problems.concat(unknown_columns(policy, table, policy.set.keys, "set"))
        end
      end

      unless policy.where.nil?
        if !policy.where.is_a?(Hash) || policy.where.empty?
          problems << invalid(policy, "where_not_hash")
        elsif table
          problems.concat(unknown_columns(policy, table, policy.where.keys, "where"))
        end
      end

      unless policy.retention.nil? || policy.retention.is_a?(ActiveSupport::Duration)
        problems << invalid(policy, "retention_not_duration")
      end

      if table
        problems << polymorphic_type_problem(policy, key, table)
        if policy.cascade && !model_for_table(table)
          problems << invalid(policy, "cascade_needs_model", table: table)
        end
        if policy.action == :scrub && policy.computed_set? && !@connection.primary_key(table)
          problems << invalid(policy, "computed_set_needs_primary_key", table: table)
        end
      end
      problems.compact
    end

    # A "table.column" for a polymorphic *_id must say which type it means,
    # or erasing User 5 would also erase what belongs to Post 5.
    def polymorphic_type_problem(policy, key, table)
      return nil unless policy.target.kind == :column

      column = key.split(".", 2).last
      return nil unless column.end_with?("_id")

      type_column = "#{column.delete_suffix("_id")}_type"
      return nil unless column_names(table).include?(type_column)
      return nil if policy.where.is_a?(Hash) && policy.where.keys.map(&:to_s).include?(type_column)

      invalid(policy, "polymorphic_type_required", key: key, type_column: type_column, subject_type: @subject.polymorphic_name)
    end

    # When the subject's row is deleted, rows that stay and point at it
    # through a foreign key would make the delete fail.
    def blocked_by_foreign_keys(results)
      return [] unless @definition.subject_policy&.destroy

      results.filter_map do |result|
        next unless result.status == :covered && result.reference&.vias&.include?(:foreign_key)

        staying = result.policies.find { |policy| %i[keep scrub].include?(policy.action) }
        invalid(staying, "kept_rows_block_destroy", key: result.key) if staying
      end
    end

    def model_for_table(table)
      models.find do |model|
        !model.abstract_class? && model.table_name == table && model.base_class == model
      rescue ActiveRecord::ActiveRecordError
        false
      end
    end

    def unknown_columns(policy, table, names, option)
      (names.map(&:to_s) - column_names(table)).map do |column|
        invalid(policy, "unknown_column", option: option, table: table, column: column)
      end
    end

    # Two policies for the same rows that say different things. The rows stay
    # covered; the second declaration is reported.
    def contradictions(by_key)
      by_key.flat_map do |key, policies|
        unconditional = policies.select { |policy| policy.where.nil? }
        next [] if unconditional.map(&:action).uniq.size < 2

        unconditional.drop(1).map do |policy|
          invalid(policy, "contradiction", key: key, other: unconditional.first.location)
        end
      end
    end

    def result_for(reference, policies)
      status =
        if policies.empty?
          reference.certain? ? :missing : :guess
        elsif policies.all?(&:ignore?)
          :ignored
        else
          :covered
        end
      Result.new(
        status: status, subject: subject_name, key: reference.key, reference: reference,
        policies: policies, message: nil, location: policies.first&.location
      )
    end

    def subject_result
      policy = @definition.subject_policy
      unless policy
        return Result.new(
          status: :missing, subject: subject_name, key: "subject", reference: nil,
          policies: [], message: nil, location: nil
        )
      end

      columns = column_names(@subject.table_name)
      message =
        if policy.destroy && policy.soft_delete
          ["subject_both", {}]
        elsif !policy.destroy && policy.soft_delete.nil?
          ["subject_neither", {}]
        elsif policy.soft_delete && !columns.include?(policy.soft_delete.to_s)
          ["unknown_column", {option: "soft_delete", table: @subject.table_name, column: policy.soft_delete.to_s}]
        elsif !policy.scrub.is_a?(Hash)
          ["subject_scrub_not_hash", {}]
        elsif (unknown = policy.scrub.keys.map(&:to_s) - columns).any?
          ["unknown_column", {option: "scrub", table: @subject.table_name, column: unknown.first}]
        end

      Result.new(
        status: message ? :invalid : :covered, subject: subject_name, key: "subject", reference: nil,
        policies: [], message: message, location: policy.location
      )
    end

    def invalid(policy, message_key, location: policy&.location, subject: subject_name, **values)
      Result.new(
        status: :invalid, subject: subject, key: policy ? policy.target.to_s : subject, reference: nil,
        policies: policy ? [policy] : [], message: [message_key, values], location: location
      )
    end

    def blank?(value)
      value.nil? || (value.is_a?(String) && value.strip.empty?)
    end
  end
end
