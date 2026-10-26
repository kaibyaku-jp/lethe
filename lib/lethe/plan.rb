# frozen_string_literal: true

module Lethe
  # What erasing one subject record will do, step by step, with the number
  # of rows each step touches. Building a plan changes nothing.
  #
  # Steps run in this order: attachments, deletions (rows that point at
  # other deleted tables first), overwrites, kept rows (nothing happens to
  # them), and the subject's own row last.
  class Plan
    include Enumerable

    Step = Data.define(:kind, :key, :policy, :location, :conditions, :count) do
      def to_s
        what =
          case kind
          when :destroy then policy.cascade ? "destroy (cascade)" : "destroy"
          when :scrub then "scrub #{policy.set.keys.join(", ")}"
          when :keep then policy.retention ? "keep for #{policy.retention.inspect}" : "keep"
          when :attachment then "purge"
          else kind.to_s
          end
        "#{what.ljust(20)} #{key.ljust(36)} #{count} #{(count == 1) ? "row" : "rows"}"
      end
    end

    attr_reader :record, :definition, :steps

    def initialize(record, definition, results, models:, connection:)
      @record = record
      @definition = definition
      @connection = connection
      @locator = Locator.new(record.class.base_class, models: models)
      @steps = build(results)
    end

    def each(&)
      steps.each(&)
    end

    def to_s
      steps.join("\n")
    end

    attr_reader :locator

    private

    def build(results)
      covered = results.select { |result| result.status == :covered && result.subject == @definition.subject_name }
      steps = covered.flat_map do |result|
        result.policies.reject(&:ignore?).map { |policy| step_for(result.key, policy) }
      end
      attachments, rest = steps.partition { |step| step.kind == :attachment }
      destroys = rest.select { |step| step.kind == :destroy }
      others = rest - destroys
      attachments + order_destroys(destroys) + others.sort_by { |step| [(step.kind == :scrub) ? 0 : 1, step.key] } + [subject_step]
    end

    def step_for(key, policy)
      if policy.action == :destroy_attachment
        return Step.new(kind: :attachment, key: key, policy: policy, location: nil, conditions: nil, count: attachment_count(policy.target.name))
      end

      location = @locator.locate(policy)
      conditions = @locator.conditions(location, policy, @record.id)
      Step.new(
        kind: policy.action, key: key, policy: policy, location: location,
        conditions: conditions, count: @locator.rows(location).where(conditions).count
      )
    end

    def attachment_count(name)
      attached = @record.public_send(name)
      if attached.respond_to?(:attachments)
        attached.attachments.size
      else
        (attached.attached? ? 1 : 0)
      end
    end

    def subject_step
      table = @record.class.table_name
      location = Locator::Location.new(table: table, column: @record.class.primary_key, type_column: nil, model: nil)
      conditions = {location.column => @record.id}
      count = Rows.for(table).where(conditions).count
      Step.new(kind: :subject, key: "subject", policy: @definition.subject_policy, location: location, conditions: conditions, count: count)
    end

    # Rows in a table with a foreign key to another table being deleted go first.
    def order_destroys(destroys)
      tables = destroys.map { |step| step.location.table }.uniq
      before = tables.to_h do |table|
        referenced = @connection.foreign_keys(table).map(&:to_table) & tables
        [table, referenced - [table]]
      end

      ordered = []
      remaining = tables.sort
      until remaining.empty?
        ready = remaining.select { |table| remaining.none? { |other| before[other].include?(table) } }
        raise Error, I18n.t("lethe.errors.foreign_key_cycle", tables: remaining.join(", ")) if ready.empty?

        ordered.concat(ready)
        remaining -= ready
      end
      destroys.sort_by { |step| [ordered.index(step.location.table), step.key] }
    end
  end
end
