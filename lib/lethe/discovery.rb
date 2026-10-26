# frozen_string_literal: true

module Lethe
  # Finds everything that points at a subject model, from the schema and the
  # models' associations. Reads table and column definitions only, never rows.
  class Discovery
    def initialize(subject, models:, connection:, configuration:)
      @subject = subject
      @models = models
      @connection = connection
      @configuration = configuration
    end

    # Returns the references, one per table.column or attachment, sorted by key.
    def call
      found = {}
      [foreign_keys, own_associations, other_associations, attachments, column_names].each do |references|
        references.each do |reference|
          found[reference.key] = found.key?(reference.key) ? found[reference.key].merge(reference) : reference
        end
      end
      found.values.sort_by(&:key)
    end

    def tables
      @tables ||= @connection.tables.reject { |table| @configuration.skipped_table?(table) }.sort
    end

    private

    def subject_table
      @subject.table_name
    end

    # Foreign key constraints that point at the subject's table.
    def foreign_keys
      tables.flat_map do |table|
        @connection.foreign_keys(table)
          .select { |key| key.to_table == subject_table }
          .map { |key| Reference.column(table, key.column, :foreign_key) }
      end
    end

    # The subject's has_many, has_one and has_and_belongs_to_many.
    def own_associations
      @subject.reflect_on_all_associations.filter_map do |reflection|
        # Through associations read other tables; has_one_attached's own
        # associations are reported as attachments instead.
        next if reflection.through_reflection? || reflection.class_name == "ActiveStorage::Attachment"

        case reflection.macro
        when :has_many, :has_one
          table = table_of(reflection)
          next unless table

          via = reflection.options[:as] ? :polymorphic : :association
          Reference.column(table, reflection.foreign_key, via)
        when :has_and_belongs_to_many
          Reference.column(reflection.join_table, reflection.foreign_key, :join_table)
        end
      end
    end

    # belongs_to in other models that points at the subject. A polymorphic
    # belongs_to might point at anything, so it is only a guess.
    def other_associations
      @models.flat_map do |model|
        next [] if model.abstract_class? || !table_exists?(model)

        model.reflect_on_all_associations(:belongs_to).filter_map do |reflection|
          if reflection.polymorphic?
            Reference.column(model.table_name, reflection.foreign_key, :polymorphic_guess)
          elsif table_of(reflection) == subject_table
            Reference.column(model.table_name, reflection.foreign_key, :association)
          end
        end
      end
    end

    def attachments
      return [] unless @subject.respond_to?(:reflect_on_all_attachments)

      @subject.reflect_on_all_attachments.map { |reflection| Reference.attachment(reflection.name) }
    end

    # Columns named like user_id or *_user_id, and the ones configured.
    def column_names
      singular = @subject.model_name.singular
      extra = @configuration.guess_columns_for(@subject.name)
      tables.flat_map do |table|
        @connection.columns(table).filter_map do |column|
          name = column.name
          next if table == subject_table && name == @subject.primary_key

          if name == "#{singular}_id" || name.end_with?("_#{singular}_id") || extra.include?(name)
            Reference.column(table, name, :column_name)
          end
        end
      end
    end

    # The table an association reads, or nil when its class cannot be loaded.
    def table_of(reflection)
      reflection.klass.table_name
    rescue NameError, ArgumentError
      nil
    end

    def table_exists?(model)
      tables.include?(model.table_name)
    rescue ActiveRecord::ActiveRecordError
      false
    end
  end
end
