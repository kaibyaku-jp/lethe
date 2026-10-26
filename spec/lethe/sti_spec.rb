# frozen_string_literal: true

require "active_support/core_ext/integer/time"
require "active_support/testing/time_helpers"

RSpec.describe "single table inheritance" do
  before do
    schema do
      create_table(:users) do |t|
        t.string :type
        t.datetime :deleted_at
      end
      create_table(:posts) { |t| t.references :user, foreign_key: true }
      create_table(:approvals) { |t| t.bigint :user_id }
      create_table(:inquiries) { |t| t.references :user, foreign_key: true }
    end
    model("Post")
    model("Approval")
    model("Inquiry")
    model("User") do
      has_many :posts
      has_many :inquiries
    end
    stub_const("Admin", Class.new(User) { has_many :approvals, foreign_key: :user_id })
    ledger_table
  end

  let(:models) { [Post, Approval, Inquiry, User, Admin] }
  let!(:member) { User.create! }
  let!(:admin) { Admin.create! }

  before do
    [member, admin].each do |user|
      Post.create!(user_id: user.id)
      Inquiry.create!(user_id: user.id)
    end
    Approval.create!(user_id: admin.id)

    Lethe.define("User") do
      subject soft_delete: :deleted_at
      destroy :posts
      keep :inquiries, for: 2.years, reason: "Support history"
    end
    Lethe.define("Admin") do
      subject soft_delete: :deleted_at
      destroy :posts
      keep :approvals, reason: "Audit"
      keep :inquiries, for: 5.years, reason: "Support history, longer for staff"
    end
  end

  it "checks the subclass on its own, guessing from the base class's user_id" do
    report = check(models)

    expect(report).to be_clean
    admin_keys = report.results.select { |result| result.subject == "Admin" && result.reference }.map(&:key)
    expect(admin_keys).to contain_exactly("approvals.user_id", "inquiries.user_id", "posts.user_id")
  end

  it "erases a subclass record by its own definition" do
    erasure = Lethe.erase!(admin, models: models)

    expect(erasure.subject).to eq("Admin")
    expect(erasure.counts).to include("approvals.user_id" => {"keep" => 0}, "posts.user_id" => {"destroy" => 1})
    expect(Approval.where(user_id: admin.id).count).to eq(1)
    expect(Lethe.leftovers(admin, models: models)).to eq([])
  end

  it "erases a base class record by the base class's definition" do
    expect(Lethe.erase!(member, models: models).subject).to eq("User")
  end

  it "sweeps each by its own retention" do
    travel_to(Time.utc(2026, 1, 1)) do
      Lethe.erase!(member, models: models)
      Lethe.erase!(admin, models: models)
    end

    swept = Lethe.sweep!(models: models, now: Time.utc(2028, 6, 1))

    expect(swept).to eq("User" => {":inquiries" => 1})
    expect(Inquiry.where(user_id: member.id)).to be_empty
    expect(Inquiry.where(user_id: admin.id).count).to eq(1)
  end

  include ActiveSupport::Testing::TimeHelpers
end
