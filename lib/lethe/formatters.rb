# frozen_string_literal: true

require "json"
require "pathname"

module Lethe
  # Turn a Report into text for people, GitHub Actions annotations, or JSON.
  module Formatters
    MARKS = {covered: "✓", ignored: "✓", missing: "✗", guess: "?", invalid: "!"}.freeze

    def self.for(name)
      case name.to_s
      when "", "text" then Text
      when "github" then GitHub
      when "json" then JSON
      else raise ArgumentError, "lethe: unknown format #{name.inspect}; use text, github or json"
      end
    end

    class Base
      # root: paths in locations are shown relative to it.
      # definition_path: where problems without a location point (the definitions file).
      def initialize(report, root: Dir.pwd, locale: I18n.default_locale, definition_path: nil)
        @report = report
        @root = Pathname(root)
        @locale = locale
        @definition_path = definition_path
      end

      private

      def t(key, **values)
        I18n.t(key, **values, locale: @locale)
      end

      # The sentence for a result that needs one.
      def message(result)
        case result.status
        when :missing
          if result.key == "subject"
            t("lethe.check.subject_missing", subject: result.subject)
          else
            t("lethe.check.missing", vias: vias(result.reference))
          end
        when :guess
          t("lethe.check.guess", vias: vias(result.reference), subject: result.subject)
        when :invalid
          key, values = result.message
          t("lethe.messages.#{key}", subject: result.subject, **values)
        end
      end

      def vias(reference)
        reference.vias.map { |via| t("lethe.vias.#{via}") }.join(t("lethe.export.list_separator"))
      end

      # [path, line] relative to root, or nil.
      def location(result)
        return nil unless result.location

        path, line = result.location.match(/\A(.*):(\d+)\z/)&.captures
        return nil unless path

        [relative(path), line.to_i]
      end

      def relative(path)
        Pathname(path).relative_path_from(@root).to_s
      rescue ArgumentError
        path
      end
    end

    class Text < Base
      def render
        lines = []
        @report.subjects.each do |subject|
          results = @report.results.select { |result| result.subject == subject }
          lines.concat(subject_lines(subject, results))
          lines << ""
        end
        lines << totals
        lines.join("\n") + "\n"
      end

      private

      def subject_lines(subject, results)
        references = results.filter_map(&:reference)
        counts = references.flat_map(&:vias).tally.sort_by { |via, _| via.to_s }
        vias = counts.map { |via, count| "#{t("lethe.vias.#{via}")} #{count}" }.join(t("lethe.export.list_separator"))
        lines = [t("lethe.check.summary", subject: subject, count: references.size, vias: vias), ""]

        covered = results.count { |result| result.reference && (result.status == :covered || result.status == :ignored) }
        lines << "#{MARKS[:covered]} #{t("lethe.check.covered", count: covered)}"

        listed = results.reject { |result| result.status == :covered || result.status == :ignored }
        width = listed.map { |result| label(result).length }.max || 0
        listed.each do |result|
          lines << "#{MARKS[result.status]} #{label(result).ljust(width)}  #{message(result)}"
        end
        lines
      end

      def label(result)
        where = location(result)
        prefix = where ? "#{where.join(":")} " : ""
        "#{prefix}#{result.key}"
      end

      def totals
        problems = @report.problems.size
        guesses = @report.strict? ? 0 : @report.count(:guess)
        return t("lethe.check.clean") if problems.zero? && guesses.zero?

        t("lethe.check.totals", problems: problems, guesses: guesses)
      end
    end

    # GitHub Actions workflow commands, one per problem or guess.
    class GitHub < Base
      def render
        @report.results.filter_map { |result| annotation(result) }.join("\n").then { |text| text.empty? ? "" : "#{text}\n" }
      end

      private

      def annotation(result)
        level =
          if result.problem?(strict: @report.strict?) then "error"
          elsif result.status == :guess then "warning"
          end
        return nil unless level

        path, line = location(result) || [@definition_path && relative(@definition_path), nil]
        properties = {"file" => path, "line" => line, "title" => "lethe: #{result.subject} #{result.key}"}
          .compact.map { |name, value| "#{name}=#{escape_property(value.to_s)}" }.join(",")
        "::#{level} #{properties}::#{escape_data(message(result))}"
      end

      # https://docs.github.com/actions/reference/workflow-commands-for-github-actions
      def escape_data(value)
        value.gsub("%", "%25").gsub("\r", "%0D").gsub("\n", "%0A")
      end

      def escape_property(value)
        escape_data(value).gsub(":", "%3A").gsub(",", "%2C")
      end
    end

    class JSON < Base
      def render
        ::JSON.pretty_generate(
          "version" => 1,
          "clean" => @report.clean?,
          "strict" => @report.strict?,
          "results" => @report.results.map { |result| entry(result) }
        ) + "\n"
      end

      private

      def entry(result)
        where = location(result)
        {
          "status" => result.status.to_s,
          "subject" => result.subject,
          "key" => result.key,
          "vias" => result.reference&.vias&.map(&:to_s),
          "actions" => result.policies.map { |policy| policy.action.to_s },
          "file" => where&.first,
          "line" => where&.last,
          "message" => message(result)
        }.compact
      end
    end
  end
end
