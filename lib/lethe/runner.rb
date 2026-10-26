# frozen_string_literal: true

require "fileutils"

module Lethe
  # Runs lethe:check and lethe:export: reads the options from the environment,
  # prints, and returns the exit status (0 clean, 1 problems, 2 cannot check).
  class Runner
    def initialize(root:, env: ENV, out: $stdout, err: $stderr, models: nil)
      @root = File.expand_path(root)
      @env = env
      @out = out
      @err = err
      @models = models
    end

    def check
      report = run_check or return 2
      formatter = Formatters.for(@env["FORMAT"]).new(report, root: @root, locale: locale, definition_path: definition_path)
      @out.print formatter.render
      report.exit_status
    rescue ArgumentError => error
      @err.puts error.message
      2
    end

    def export
      report = run_check or return 2
      unless report.clean?
        @err.print Formatters::Text.new(report, root: @root, locale: locale, definition_path: definition_path).render
        return 1
      end

      exporter = Exporter.new(
        report, definitions: Lethe.definitions.values, models: models, root: @root,
        definition_path: definition_path, locale: locale
      )
      files = {"#{export_path}.md" => exporter.markdown, "#{export_path}.json" => exporter.json}
      truthy?(@env["CHECK"]) ? compare(files) : write(files)
    end

    private

    def run_check
      return nil unless valid_locale?

      Lethe.load_definitions(definition_path)
      Lethe.check(models: models, strict: truthy?(@env["STRICT"]))
    rescue DefinitionError => error
      @err.puts error.message
      nil
    rescue ScriptError, StandardError => error
      @err.puts I18n.t("lethe.errors.load_failed", path: relative(definition_path), error: "#{error.class}: #{error.message}", locale: locale)
      nil
    end

    def compare(files)
      stale = files.reject { |path, content| File.file?(path) && File.read(path) == content }
      if stale.empty?
        @out.puts "lethe: #{files.keys.map { |path| relative(path) }.join(", ")} up to date"
        0
      else
        @err.puts "lethe: #{stale.keys.map { |path| relative(path) }.join(", ")} out of date; run bin/rails lethe:export"
        1
      end
    end

    def write(files)
      files.each do |path, content|
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)
        @out.puts "lethe: wrote #{relative(path)}"
      end
      0
    end

    def models
      @models || ActiveRecord::Base.descendants.reject { |model| model.abstract_class? || model.name.nil? }
    end

    def definition_path
      File.expand_path(Lethe.configuration.definition_path, @root)
    end

    def export_path
      File.expand_path(Lethe.configuration.export_path, @root)
    end

    def locale
      (@env["LOCALE"].nil? || @env["LOCALE"].empty?) ? I18n.default_locale : @env["LOCALE"].to_sym
    end

    def valid_locale?
      return true if I18n.available_locales.include?(locale)

      @err.puts "lethe: LOCALE=#{locale} is not one of #{I18n.available_locales.join(", ")}"
      false
    end

    def truthy?(value)
      %w[1 true yes].include?(value.to_s.downcase)
    end

    def relative(path)
      Pathname(path).relative_path_from(Pathname(@root)).to_s
    rescue ArgumentError
      path.to_s
    end
  end
end
