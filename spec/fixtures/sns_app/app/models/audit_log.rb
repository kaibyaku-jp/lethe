# frozen_string_literal: true

class AuditLog < ApplicationRecord
  belongs_to :admin_user
end
