# frozen_string_literal: true

module Lethe
  # What a policy points at, as written in the definitions:
  # an association of the subject (:ratings), a "table.column" string,
  # or an attachment of the subject.
  Target = Data.define(:kind, :name, :table, :column) do
    def self.parse(value)
      case value
      when Symbol
        new(kind: :association, name: value, table: nil, column: nil)
      when String
        table, column, rest = value.split(".")
        unless rest.nil? && present?(table) && present?(column)
          raise ArgumentError, "lethe: #{value.inspect} is not \"table.column\"; use a symbol for an association"
        end
        new(kind: :column, name: value, table: table, column: column)
      else
        raise ArgumentError, "lethe: #{value.inspect} must be an association name (a Symbol) or \"table.column\""
      end
    end

    def self.attachment(value)
      raise ArgumentError, "lethe: attachment #{value.inspect} must be a Symbol" unless value.is_a?(Symbol)

      new(kind: :attachment, name: value, table: nil, column: nil)
    end

    def self.present?(part)
      !part.nil? && !part.empty?
    end
    private_class_method :present?

    def to_s
      case kind
      when :association then ":#{name}"
      when :attachment then "attachment :#{name}"
      else name
      end
    end
  end
end
