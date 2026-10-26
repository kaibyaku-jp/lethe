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

  create_table :active_storage_blobs, force: :cascade do |t|
    t.string :key, null: false
    t.string :filename, null: false
    t.string :content_type
    t.text :metadata
    t.string :service_name, null: false
    t.bigint :byte_size, null: false
    t.string :checksum
    t.datetime :created_at, null: false
    t.index [:key], unique: true
  end

  create_table :active_storage_attachments, force: :cascade do |t|
    t.string :name, null: false
    t.references :record, null: false, polymorphic: true, index: false
    t.references :blob, null: false, foreign_key: {to_table: :active_storage_blobs}
    t.datetime :created_at, null: false
  end

  create_table :active_storage_variant_records, force: :cascade do |t|
    t.references :blob, null: false, foreign_key: {to_table: :active_storage_blobs}
    t.string :variation_digest, null: false
  end

  create_table :lethe_erasures, force: :cascade do |t|
    t.string :subject_type, null: false
    t.string :subject_id, null: false
    t.string :kind, null: false
    t.text :counts, null: false
    t.datetime :created_at, null: false
  end
end
