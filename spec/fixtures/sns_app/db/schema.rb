# frozen_string_literal: true

ActiveRecord::Schema.define do
  create_table :users, force: :cascade do |t|
    t.string :nickname
    t.string :email
    t.datetime :deleted_at
  end

  create_table :posts, force: :cascade do |t|
    t.references :user, foreign_key: true
    t.text :body
  end

  create_table :follows, force: :cascade do |t|
    t.bigint :follower_id
    t.bigint :following_id
  end

  create_table :muted_users, force: :cascade do |t|
    t.references :user, foreign_key: true
    t.bigint :muted_user_id
  end

  create_table :inquiries, force: :cascade do |t|
    t.references :user, foreign_key: true
    t.string :email
    t.text :message
  end

  create_table :admin_users, force: :cascade do |t|
    t.string :email
  end

  create_table :audit_logs, force: :cascade do |t|
    t.bigint :admin_user_id
    t.string :action
  end
end
