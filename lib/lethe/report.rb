# frozen_string_literal: true

module Lethe
  class Report
    attr_reader :results

    def initialize(results, strict: false)
      @results = results
      @strict = strict
    end

    def strict?
      @strict
    end

    def problems
      results.select { |result| result.problem?(strict: @strict) }
    end

    def clean?
      problems.empty?
    end

    def exit_status
      clean? ? 0 : 1
    end

    def count(status)
      results.count { |result| result.status == status }
    end

    def subjects
      results.map(&:subject).uniq
    end
  end
end
