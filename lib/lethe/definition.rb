# frozen_string_literal: true

module Lethe
  # The policies declared for one subject, such as User.
  class Definition
    attr_reader :subject_name, :policies
    attr_accessor :subject_policy

    def initialize(subject_name)
      @subject_name = subject_name
      @policies = []
      @subject_policy = nil
    end

    # The methods available inside Lethe.define.
    class Builder
      def initialize(definition)
        @definition = definition
      end

      # Delete the rows.
      def destroy(*targets, reason: nil, where: nil)
        add(:destroy, targets, location: caller_location, reason: reason, where: where)
      end

      # Keep the rows but overwrite columns: scrub :posts, set: { body: "" }
      def scrub(*targets, set:, reason: nil, where: nil)
        add(:scrub, targets, location: caller_location, reason: reason, where: where, set: set)
      end

      # Leave the rows as they are, for a reason: keep :orders, for: 7.years, reason: "..."
      def keep(*targets, reason: nil, where: nil, **options)
        unknown = options.keys - [:for]
        raise ArgumentError, "lethe: unknown keyword#{"s" if unknown.size > 1}: #{unknown.join(", ")}" if unknown.any?

        add(:keep, targets, location: caller_location, reason: reason, where: where, retention: options[:for])
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
            retention: nil, where: nil, set: nil, location: location
          )
        end
      end

      # How the subject's own row goes: subject soft_delete: :deleted_at, scrub: { email: nil }
      def subject(destroy: false, soft_delete: nil, scrub: {})
        @definition.subject_policy = SubjectPolicy.new(
          destroy: destroy, soft_delete: soft_delete, scrub: scrub, location: caller_location
        )
      end

      private

      def add(action, targets, location:, reason: nil, where: nil, set: nil, retention: nil)
        raise ArgumentError, "lethe: #{action} needs at least one target" if targets.empty?

        targets.each do |value|
          @definition.policies << Policy.new(
            action: action, target: Target.parse(value), reason: reason,
            retention: retention, where: where, set: set, location: location
          )
        end
      end

      def caller_location
        location = caller_locations(2, 1).first
        "#{location.path}:#{location.lineno}"
      end
    end
  end
end
