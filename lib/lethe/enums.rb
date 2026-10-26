# frozen_string_literal: true

module Lethe
  # lethe reaches rows through plain table classes, which know nothing of the
  # application's enums: { status: "answered" } would become status = NULL
  # and match nothing. These turn enum names into the values stored, using
  # the application's model for the table.
  module Enums
    # The hash with enum names replaced by their stored values. Values that
    # are not enum names, such as nil or a stored value, stay as they are.
    def self.cast(model, hash)
      return hash unless model && hash.is_a?(Hash)

      enums = model.defined_enums
      hash.to_h do |column, value|
        mapping = enums[column.to_s]
        [column, mapping ? cast_value(mapping, value) : value]
      end
    end

    # The names in hash that are neither a name nor a stored value of the
    # column's enum, as [column, value] pairs.
    def self.unknown(model, hash)
      return [] unless model && hash.is_a?(Hash)

      hash.flat_map do |column, value|
        mapping = model.defined_enums[column.to_s]
        next [] unless mapping

        Array(value).reject { |item| item.nil? || item.is_a?(Proc) || known?(mapping, item) }.map { |item| [column.to_s, item] }
      end
    end

    def self.cast_value(mapping, value)
      return value.map { |item| cast_value(mapping, item) } if value.is_a?(Array)
      return mapping[value.to_s] if (value.is_a?(String) || value.is_a?(Symbol)) && mapping.key?(value.to_s)

      value
    end

    def self.known?(mapping, item)
      mapping.key?(item.to_s) || mapping.value?(item)
    end
    private_class_method :cast_value, :known?
  end
end
