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
      by_key, problems = declared_keys

      results = problems + contradictions(by_key)
      results.concat(discovery.call.map { |reference| result_for(reference, by_key.delete(reference.key) || []) })
      # Declared and valid, but not something Discovery found: trust the declaration.
      results.concat(by_key.map { |key, policies| result_for(Reference.column(*key.split(".", 2), :declared), policies) })
      results << subject_result
      results.concat(blocked_by_foreign_keys(results))
    end

    # The schema questions Rules asks.
    def column_names(table)
      @column_names ||= {}
      @column_names[table] ||= @connection.columns(table).map(&:name)
    end

    def model_for_table(table)
      models.find do |model|
        !model.abstract_class? && model.table_name == table && model.base_class == model
      rescue ActiveRecord::ActiveRecordError
        false
      end
    end

    def primary_key(table)
      @connection.primary_key(table)
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

    # { "table.column" => [valid policies] }, and the problems with the rest.
    def declared_keys
      rules = Rules.new(@subject, self) { |policy, message_key, **values| invalid(policy, message_key, **values) }
      problems = []
      by_key = Hash.new { |hash, key| hash[key] = [] }
      @definition.policies.each do |policy|
        key, error = resolve(policy)
        next problems << error if error

        found = rules.call(policy, key)
        found.empty? ? by_key[key] << policy : problems.concat(found)
      end
      [by_key, problems]
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
      message = policy ? subject_problem(policy) : nil
      Result.new(
        status: if policy.nil?
                  :missing
                else
                  (message ? :invalid : :covered)
                end, subject: subject_name, key: "subject",
        reference: nil, policies: [], message: message, location: policy&.location
      )
    end

    # What is wrong with the subject declaration, as [message key, values], or nil.
    def subject_problem(policy)
      table = @subject.table_name
      columns = column_names(table)
      return ["subject_both", {}] if policy.destroy && policy.soft_delete
      return ["subject_neither", {}] if !policy.destroy && policy.soft_delete.nil?
      if policy.soft_delete && !columns.include?(policy.soft_delete.to_s)
        return ["unknown_column", {option: "soft_delete", table: table, column: policy.soft_delete.to_s}]
      end
      return ["subject_scrub_not_hash", {}] unless policy.scrub.is_a?(Hash)

      unknown = policy.scrub.keys.map(&:to_s) - columns
      return ["unknown_column", {option: "scrub", table: table, column: unknown.first}] if unknown.any?

      column, value = Enums.unknown(@subject, policy.scrub).first
      ["unknown_enum_value", {option: "scrub", table: table, column: column, value: value.inspect}] if column
    end

    def invalid(policy, message_key, location: policy&.location, subject: subject_name, **values)
      Result.new(
        status: :invalid, subject: subject, key: policy ? policy.target.to_s : subject, reference: nil,
        policies: policy ? [policy] : [], message: [message_key, values], location: location
      )
    end
  end
end
