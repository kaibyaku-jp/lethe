# frozen_string_literal: true

require "json"
require "pathname"

module Lethe
  # Writes what happens to each kind of data when a subject leaves, as a
  # Markdown table for people and as JSON for tools. Only covered references
  # appear; ignored ones do not point at the subject.
  class Exporter
    def initialize(report, definitions:, models:, root:, definition_path:, locale: I18n.default_locale)
      @report = report
      @definitions = definitions
      @models = models
      @root = Pathname(root)
      @definition_path = definition_path
      @locale = locale
    end

    def markdown
      sections = subjects.map { |subject| markdown_section(subject) }
      "<!-- #{t("lethe.export.generated", path: relative(@definition_path))} -->\n\n#{sections.join("\n")}"
    end

    def json
      ::JSON.pretty_generate(
        "version" => 1,
        "subjects" => subjects.map { |subject| json_subject(subject) }
      ) + "\n"
    end

    private

    def subjects
      @definitions.map(&:subject_name).select { |name| @report.subjects.include?(name) }.sort
    end

    def rows(subject)
      @report.results
        .select { |result| result.subject == subject && result.status == :covered && result.reference }
        .sort_by(&:key)
        .flat_map { |result| result.policies.reject(&:ignore?).map { |policy| [result.reference, policy] } }
    end

    def markdown_section(subject)
      lines = [
        "# #{t("lethe.export.title", subject: subject_label(subject))}",
        "",
        "| #{t("lethe.export.data")} | #{t("lethe.export.action")} | #{t("lethe.export.retention")} | #{t("lethe.export.reason")} |",
        "| --- | --- | --- | --- |"
      ]
      definition = definition_for(subject)
      if definition.subject_policy
        lines << row([t("lethe.export.subject_row", subject: subject_label(subject)), subject_action(definition.subject_policy), "", ""])
      end
      rows(subject).each do |reference, policy|
        lines << row([label(subject, reference), action(policy), retention(policy.retention), policy.reason.to_s])
      end
      lines.join("\n") + "\n"
    end

    def json_subject(subject)
      definition = definition_for(subject)
      subject_policy = definition.subject_policy
      {
        "subject" => subject,
        "subject_row" => subject_policy && {
          "destroy" => subject_policy.destroy ? true : false,
          "soft_delete" => subject_policy.soft_delete&.to_s,
          "scrub" => subject_policy.scrub.keys.map(&:to_s)
        }.compact,
        "data" => rows(subject).map do |reference, policy|
          {
            "key" => reference.key,
            "table" => reference.table,
            "column" => reference.column,
            "attachment" => reference.attachment,
            "label" => label(subject, reference),
            "action" => policy.action.to_s,
            "where" => policy.where&.transform_keys(&:to_s),
            "set" => policy.set&.keys&.map(&:to_s),
            "retention_seconds" => policy.retention&.to_i,
            "retention" => policy.retention && retention(policy.retention),
            "reason" => policy.reason
          }.compact
        end
      }.compact
    end

    def definition_for(subject)
      @definitions.find { |definition| definition.subject_name == subject }
    end

    def subject_model(subject)
      subject.safe_constantize
    end

    def subject_label(subject)
      model = subject_model(subject)
      model ? model.model_name.human(locale: @locale) : subject
    end

    def label(subject, reference)
      if reference.attachment
        model = subject_model(subject)
        name = model ? model.human_attribute_name(reference.attachment, locale: @locale) : reference.attachment
        return t("lethe.export.attachment", name: name)
      end

      model = @models.find { |candidate| candidate.table_name == reference.table && candidate.base_class == candidate }
      base = model ? model.model_name.human(locale: @locale) : reference.table
      conventional = subject_model(subject)&.model_name&.singular&.then { |singular| "#{singular}_id" }
      (reference.column == conventional) ? base : t("lethe.export.column_suffix", label: base, column: reference.column)
    end

    def action(policy)
      text =
        case policy.action
        when :scrub then t("lethe.export.scrub", columns: list(policy.set.keys))
        else t("lethe.export.#{policy.action}")
        end
      return text unless policy.where

      conditions = policy.where.map { |column, value| "#{column} = #{Array(value).join(" / ")}" }
      t("lethe.export.where", action: text, conditions: conditions.join(t("lethe.export.list_separator")))
    end

    def subject_action(policy)
      return t("lethe.export.destroy") if policy.destroy

      scrubbed = policy.scrub.keys
      if scrubbed.empty?
        t("lethe.export.soft_delete", column: policy.soft_delete)
      else
        t("lethe.export.soft_delete_scrub", column: policy.soft_delete, columns: list(scrubbed))
      end
    end

    def retention(duration)
      return "" unless duration

      duration.parts.map { |unit, count| t("lethe.export.parts.#{unit}", count: count) }.join(" ")
    end

    def list(names)
      names.join(t("lethe.export.list_separator"))
    end

    def row(cells)
      "| #{cells.map { |cell| cell.to_s.gsub("|", "\\|").gsub(/\s*\n\s*/, " ") }.join(" | ")} |"
    end

    def relative(path)
      Pathname(path).relative_path_from(@root).to_s
    rescue ArgumentError
      path.to_s
    end

    def t(key, **values)
      I18n.t(key, **values, locale: @locale)
    end
  end
end
