# frozen_string_literal: true

require "active_record"
require "i18n"
require_relative "lethe/version"
require_relative "lethe/configuration"
require_relative "lethe/target"
require_relative "lethe/policy"
require_relative "lethe/definition"
require_relative "lethe/reference"
require_relative "lethe/discovery"
require_relative "lethe/result"
require_relative "lethe/report"
require_relative "lethe/checker"
require_relative "lethe/formatters"
require_relative "lethe/exporter"
require_relative "lethe/runner"

# Declares what happens to the data that points at a model, such as User,
# when that record goes away, and finds the tables nobody declared.
module Lethe
  class Error < StandardError; end

  # The definitions file could not be read, or names something that is not a model.
  class DefinitionError < Error; end

  # Raised by Lethe.check! when the check finds problems.
  class Unclean < Error
    attr_reader :report

    def initialize(report)
      @report = report
      super(Formatters::Text.new(report).render)
    end
  end

  I18n.load_path += Dir[File.join(__dir__, "lethe", "locales", "*.yml")]

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
    end

    # The definitions declared so far, keyed by subject class name.
    def definitions
      @definitions ||= {}
    end

    # Declares the policies for one subject. Calling it again for the same
    # subject adds to what was declared before.
    def define(subject, &block)
      raise ArgumentError, "Lethe.define needs a block" unless block

      name = subject.is_a?(Module) ? subject.name : subject.to_s
      raise ArgumentError, "Lethe.define needs a class or a class name" if name.nil? || name.empty?

      definition = definitions[name] ||= Definition.new(name)
      Definition::Builder.new(definition).instance_exec(&block)
      definition
    end

    # Forgets every definition, then loads the definitions file.
    def load_definitions(path)
      raise DefinitionError, I18n.t("lethe.errors.no_definitions_file", path: path.to_s) unless File.file?(path)

      reset_definitions!
      load File.expand_path(path)
      definitions
    end

    def reset_definitions!
      @definitions = {}
    end

    def reset!
      reset_definitions!
      @configuration = nil
    end

    # Checks every definition against the schema and returns a Report.
    # models defaults to every loaded Active Record model with a table.
    def check(definitions: self.definitions.values, models: nil, connection: nil, strict: false)
      run = lambda do |conn|
        definitions.flat_map do |definition|
          Checker.new(definition, models: models, connection: conn, configuration: configuration).call
        end
      end
      results = connection ? run.call(connection) : ActiveRecord::Base.with_connection(&run)
      Report.new(results, strict: strict)
    end

    # Like check, but raises Lethe::Unclean when there are problems. For tests.
    def check!(**options)
      report = check(**options)
      raise Unclean, report unless report.clean?

      report
    end
  end
end

require_relative "lethe/railtie" if defined?(Rails::Railtie)
