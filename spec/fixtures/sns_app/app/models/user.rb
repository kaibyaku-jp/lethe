# frozen_string_literal: true

class User < ApplicationRecord
  has_many :posts
  has_many :muted_users
  has_many :inquiries, dependent: :destroy
  has_one_attached :avatar
end
