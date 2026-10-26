# frozen_string_literal: true

module Lethe
  # Something that points at a subject: a table's column, or an attachment.
  #
  # vias says how it was found. Foreign keys, associations and attachments
  # are certain; a column name alone, or a polymorphic belongs_to the subject
  # does not answer with an `as:` association, is only a guess.
  Reference = Data.define(:table, :column, :attachment, :vias) do
    def self.column(table, column, via)
      new(table: table.to_s, column: column.to_s, attachment: nil, vias: [via])
    end

    def self.attachment(name)
      new(table: nil, column: nil, attachment: name.to_s, vias: [:attachment])
    end

    def key
      attachment ? "attachment:#{attachment}" : "#{table}.#{column}"
    end

    def certain?
      vias.any? { |via| self.class::CERTAIN_VIAS.include?(via) }
    end

    def merge(other)
      with(vias: self.class.order(vias + other.vias))
    end

    # Clues in a fixed order, the most certain first, so output does not
    # depend on which clue found a reference first.
    def self.order(vias)
      vias.uniq.sort_by { |via| self::VIA_ORDER.index(via) || self::VIA_ORDER.size }
    end

    def to_s
      attachment ? "attachment :#{attachment}" : key
    end
  end

  Reference::CERTAIN_VIAS = %i[foreign_key association join_table polymorphic attachment declared].freeze
  Reference::VIA_ORDER = (Reference::CERTAIN_VIAS + %i[polymorphic_guess column_name]).freeze
end
