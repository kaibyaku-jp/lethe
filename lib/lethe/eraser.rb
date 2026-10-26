# frozen_string_literal: true

module Lethe
  # Carries out a Plan in one transaction. Attachments are detached inside
  # it; their files are purged only after it commits, since files cannot be
  # rolled back.
  class Eraser
    Erasure = Data.define(:subject, :id, :counts)

    def initialize(plan, configuration:, ledger:)
      @plan = plan
      @record = plan.record
      @definition = plan.definition
      @configuration = configuration
      @ledger = ledger
    end

    def call
      blobs = []
      counts = {}
      ActiveRecord::Base.transaction do
        @definition.hooks_for(:before).each { |hook| hook.block.call(@record) }
        # { "posts.user_id" => { "destroy" => 1, "scrub" => 4 } }: a table can have a policy per condition.
        @plan.each do |step|
          rows = perform(step, blobs)
          (counts[step.key] ||= Hash.new(0))[step.kind.to_s] += rows
        end
        @definition.hooks_for(:after).each { |hook| hook.block.call(@record) }
        Ledger.record(subject_type, @record.id, "erase", counts) if @ledger
      end

      erasure = Erasure.new(subject: subject_type, id: @record.id, counts: counts)
      ActiveRecord.after_all_transactions_commit do
        purge(blobs)
        ActiveSupport::Notifications.instrument("erase.lethe", subject: erasure.subject, id: erasure.id, counts: counts)
      end
      erasure
    end

    private

    # The definition's subject, so that an STI subclass with a definition of
    # its own is swept by its own retention.
    def subject_type
      @definition.subject_name
    end

    def perform(step, blobs)
      case step.kind
      when :attachment then detach(step.policy.target.name, blobs)
      when :destroy then destroy(step)
      when :scrub then scrub(step)
      when :keep then 0
      when :subject then erase_subject(step)
      end
    end

    def destroy(step)
      if step.policy.cascade
        step.location.model.unscoped.where(step.conditions).destroy_all.size
      else
        rows(step).where(step.conditions).delete_all
      end
    end

    def scrub(step)
      set = step.policy.set
      unless step.policy.computed_set?
        return rows(step).where(step.conditions).update_all(Enums.cast(step.location.model, set))
      end

      count = 0
      rows(step).where(step.conditions).find_each do |row|
        row.update_columns(Enums.cast(step.location.model, evaluate(set, row)))
        count += 1
      end
      count
    end

    def erase_subject(step)
      policy = step.policy
      relation = rows(step).where(step.conditions)
      return relation.delete_all if policy.destroy

      # The first erasure's time stays, so that retention counts from it.
      relation.where(policy.soft_delete => nil).update_all(policy.soft_delete => Time.current)
      relation.update_all(Enums.cast(@record.class, evaluate(policy.scrub, @record))) unless policy.scrub.empty?
      relation.count
    end

    def detach(name, blobs)
      attached = @record.public_send(name)
      attachments = attached.respond_to?(:attachments) ? attached.attachments.to_a : [attached.attachment].compact
      blobs.concat(attachments.map(&:blob))
      attached.detach if attachments.any?
      attachments.size
    end

    def purge(blobs)
      blobs.each { |blob| (@configuration.purge == :now) ? blob.purge : blob.purge_later }
    end

    def evaluate(set, row)
      set.to_h do |column, value|
        next [column, value] unless value.is_a?(Proc)

        [column, value.arity.zero? ? value.call : value.call(row)]
      end
    end

    def rows(step)
      Rows.for(step.location.table)
    end
  end
end
