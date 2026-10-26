# frozen_string_literal: true

require "json"

module Lethe
  # The lethe_erasures table: one row each time a subject is erased or its
  # kept rows are swept, with the subject's class, id and the number of rows
  # per table. Never anything personal. bin/rails generate lethe:install
  # creates it.
  module Ledger
    TABLE = "lethe_erasures"

    def self.available?(connection)
      connection.data_source_exists?(TABLE)
    end

    def self.record(subject_type, subject_id, kind, counts)
      Rows.for(TABLE).create!(
        subject_type: subject_type, subject_id: subject_id.to_s, kind: kind,
        counts: JSON.generate(counts), created_at: Time.current
      )
    end

    # { subject_id => when it was first erased }
    def self.erased(subject_type)
      Rows.for(TABLE).where(subject_type: subject_type, kind: "erase").group(:subject_id).minimum(:created_at)
    end
  end
end
