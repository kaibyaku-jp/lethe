# frozen_string_literal: true

module Lethe
  # What the check concluded about one reference or one declaration.
  #
  #   status    :covered  a policy applies
  #             :ignored  declared not to point at the subject
  #             :missing  certainly points at the subject, and nothing is declared
  #             :guess    might point at the subject, and nothing is declared
  #             :invalid  a declaration is wrong or names something that is gone
  #   subject   the subject class name
  #   key       "table.column", "attachment:name" or "subject" for the subject's own row
  #   reference the Reference, when there is one
  #   policies  the policies that apply
  #   message   an I18n key and its values, for :invalid
  #   location  "path:line" of the declaration, when there is one
  Result = Data.define(:status, :subject, :key, :reference, :policies, :message, :location) do
    def problem?(strict: false)
      status == :missing || status == :invalid || (strict && status == :guess)
    end
  end
end
