# frozen_string_literal: true

module Lethe
  # Plain Active Record classes for reaching a table's rows without the
  # application's model: no default scopes, callbacks or single table
  # inheritance get in the way of deleting or overwriting exactly the rows
  # a policy names. One class per table, made once.
  module Rows
    @classes = {}
    @mutex = Mutex.new

    # Forgets the classes, for when the schema changes in the same process.
    def self.reset!
      @mutex.synchronize { @classes.clear }
    end

    def self.for(table)
      @mutex.synchronize do
        @classes[table] ||= Class.new(ActiveRecord::Base) do
          self.table_name = table
          self.inheritance_column = nil

          def self.name
            "Lethe::Rows"
          end
        end
      end
    end
  end

  # The application's models, leaving out the classes lethe makes.
  def self.application_models
    ActiveRecord::Base.descendants.reject do |model|
      model.abstract_class? || model.name.nil? || model.name.start_with?("Lethe::")
    end
  end
end
