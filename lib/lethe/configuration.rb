# frozen_string_literal: true

module Lethe
  class Configuration
    # Tables Rails and lethe keep for themselves. Active Storage's are left
    # out because attachments are found through has_one_attached and
    # has_many_attached, and declared with destroy_attachments.
    BUILTIN_SKIP_TABLES = %w[
      ar_internal_metadata schema_migrations lethe_erasures
      active_storage_attachments active_storage_blobs active_storage_variant_records
    ].freeze

    # Where the definitions live, relative to the application root.
    attr_accessor :definition_path

    # Where lethe:export writes, without extension: .md and .json are added.
    attr_accessor :export_path

    # Tables to leave out of the search, besides Rails' own.
    attr_accessor :skip_tables

    # How erased attachments' files go, after the transaction commits:
    # :later through Active Storage's purge job, or :now.
    attr_reader :purge

    def initialize
      @definition_path = "config/lethe.rb"
      @export_path = "docs/lethe"
      @skip_tables = []
      @purge = :later
      @guess_columns = Hash.new { |hash, key| hash[key] = [] }
    end

    # More column names to treat as pointing at a subject, per subject:
    #   config.guess_columns[User] = %w[follower_id following_id]
    def guess_columns
      GuessColumns.new(@guess_columns)
    end

    def purge=(value)
      raise ArgumentError, "lethe: purge must be :later or :now" unless %i[later now].include?(value)

      @purge = value
    end

    def guess_columns_for(subject_name)
      @guess_columns.fetch(subject_name, []).map(&:to_s)
    end

    def skipped_table?(table)
      BUILTIN_SKIP_TABLES.include?(table) || skip_tables.map(&:to_s).include?(table)
    end

    # Lets guess_columns be keyed by the class or its name.
    class GuessColumns
      def initialize(store)
        @store = store
      end

      def [](subject)
        @store[key(subject)]
      end

      def []=(subject, columns)
        @store[key(subject)] = Array(columns).map(&:to_s)
      end

      private

      def key(subject)
        subject.is_a?(Module) ? subject.name : subject.to_s
      end
    end
  end
end
