# frozen_string_literal: true

module Lethe
  # The policies declared for one subject, such as User.
  class Definition
    attr_reader :subject_name, :policies, :hooks
    attr_accessor :subject_policy

    def initialize(subject_name)
      @subject_name = subject_name
      @policies = []
      @hooks = []
      @subject_policy = nil
    end

    def hooks_for(moment)
      hooks.select { |hook| hook.moment == moment }
    end

    # The methods available inside Lethe.define.
    class Builder
      def initialize(definition)
        @definition = definition
      end

      # Delete the rows. cascade: true deletes them through Active Record,
      # so that dependent: associations, callbacks and attachments go too.
      def destroy(*targets, reason: nil, where: nil, cascade: false)
        add(:destroy, targets, location: caller_location, reason: reason, where: where, cascade: cascade)
      end

      # Keep the rows but overwrite columns: scrub :posts, set: { body: "" }
      # With for:, lethe:sweep deletes the rows once that time has passed:
      # scrub :orders, set: { phone: nil }, for: 7.years. cascade: true makes
      # that deletion go through Active Record, as with destroy.
      def scrub(*targets, set:, reason: nil, where: nil, cascade: false, **options)
        add(:scrub, targets, location: caller_location, reason: reason, where: where, set: set,
          retention: retention(options), cascade: cascade)
      end

      # Leave the rows as they are, for a reason: keep :orders, for: 7.years, reason: "..."
      def keep(*targets, reason: nil, where: nil, cascade: false, **options)
        add(:keep, targets, location: caller_location, reason: reason, where: where,
          retention: retention(options), cascade: cascade)
      end

      # The column does not point at the subject after all (a wrong guess).
      def ignore(*targets, reason: nil)
        add(:ignore, targets, location: caller_location, reason: reason)
      end

      # Delete Active Storage attachments of the subject.
      def destroy_attachments(*names, reason: nil)
        raise ArgumentError, "lethe: destroy_attachments needs at least one name" if names.empty?

        location = caller_location
        names.each do |name|
          @definition.policies << Policy.new(
            action: :destroy_attachment, target: Target.attachment(name), reason: reason,
            retention: nil, where: nil, set: nil, cascade: false, location: location
          )
        end
      end

      # How the subject's own row goes: subject soft_delete: :deleted_at, scrub: { email: nil }
      def subject(destroy: false, soft_delete: nil, scrub: {})
        @definition.subject_policy = SubjectPolicy.new(
          destroy: destroy, soft_delete: soft_delete, scrub: scrub, location: caller_location
        )
      end

      # Runs inside the erasure's transaction, before anything is deleted.
      def before_erase(&block)
        hook(:before, block)
      end

      # Runs inside the erasure's transaction, after everything is deleted.
      # Anything that cannot be rolled back, such as a call to another
      # service, belongs in a job enqueued from here.
      def after_erase(&block)
        hook(:after, block)
      end

      private

      # for: is a Ruby keyword, so it arrives in the options hash.
      def retention(options)
        unknown = options.keys - [:for]
        raise ArgumentError, "lethe: unknown keyword#{"s" if unknown.size > 1}: #{unknown.join(", ")}" if unknown.any?

        options[:for]
      end

      def add(action, targets, location:, reason: nil, where: nil, set: nil, retention: nil, cascade: false)
        raise ArgumentError, "lethe: #{action} needs at least one target" if targets.empty?

        targets.each do |value|
          @definition.policies << Policy.new(
            action: action, target: Target.parse(value), reason: reason,
            retention: retention, where: where, set: set, cascade: cascade ? true : false, location: location
          )
        end
      end

      def hook(moment, block)
        raise ArgumentError, "lethe: #{moment}_erase needs a block" unless block

        location = caller_locations(2, 1).first
        @definition.hooks << Hook.new(moment: moment, block: block, location: "#{location.path}:#{location.lineno}")
      end

      def caller_location
        location = caller_locations(2, 1).first
        "#{location.path}:#{location.lineno}"
      end
    end
  end
end
