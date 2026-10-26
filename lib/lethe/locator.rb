# frozen_string_literal: true

module Lethe
  # Finds the rows a policy applies to, for one subject: the table, the
  # column holding the subject's id, the polymorphic type column when there
  # is one, and the application's model when cascade needs it.
  class Locator
    Location = Data.define(:table, :column, :type_column, :model)

    def initialize(subject, models:)
      @subject = subject
      @models = models
    end

    def locate(policy)
      target = policy.target
      case target.kind
      when :association then locate_association(target.name)
      when :column then Location.new(table: target.table, column: target.column, type_column: nil, model: model_for(target.table))
      else raise ArgumentError, "lethe: attachments have no table to locate"
      end
    end

    # Conditions for the rows of one subject id (or several), with the
    # polymorphic type and the policy's own where:.
    def conditions(location, policy, id)
      conditions = {location.column => id}
      conditions[location.type_column] = @subject.polymorphic_name if location.type_column
      conditions.merge((policy&.where || {}).transform_keys(&:to_s))
    end

    def rows(location)
      Rows.for(location.table)
    end

    private

    def locate_association(name)
      reflection = @subject.reflect_on_association(name)
      if reflection.options[:primary_key]
        raise Error, "lethe: :#{name} uses primary_key:, which lethe does not support yet"
      end

      if reflection.macro == :has_and_belongs_to_many
        Location.new(table: reflection.join_table.to_s, column: reflection.foreign_key.to_s, type_column: nil, model: nil)
      else
        type_column = reflection.options[:as] ? reflection.type.to_s : nil
        Location.new(
          table: reflection.klass.table_name, column: reflection.foreign_key.to_s,
          type_column: type_column, model: reflection.klass
        )
      end
    end

    def model_for(table)
      @models.find { |model| model.table_name == table && model.base_class == model }
    end
  end
end
