# frozen_string_literal: true

require "active_support/core_ext/integer/time"

RSpec.describe Lethe::Definition do
  def define(&block)
    Lethe.define("User", &block)
  end

  it "records each policy with the line it was declared on" do
    line = __LINE__ + 2
    definition = define do
      destroy :ratings, :favorites, reason: "nobody else needs them"
    end

    expect(definition.policies.map(&:action)).to eq(%i[destroy destroy])
    expect(definition.policies.map { |policy| policy.target.name }).to eq(%i[ratings favorites])
    expect(definition.policies.map(&:reason).uniq).to eq(["nobody else needs them"])
    expect(definition.policies.map(&:location).uniq).to eq(["#{__FILE__}:#{line}"])
  end

  it "records scrub with the columns to overwrite and a condition" do
    definition = define do
      scrub :questions, set: {body: ""}, where: {status: "answered"}
    end

    policy = definition.policies.sole
    expect(policy).to have_attributes(action: :scrub, set: {body: ""}, where: {status: "answered"})
  end

  it "records keep with how long and why" do
    definition = define do
      keep "inquiries.user_id", for: 2.years, reason: "support history"
    end

    policy = definition.policies.sole
    expect(policy).to have_attributes(action: :keep, retention: 2.years, reason: "support history")
    expect(policy.target).to have_attributes(kind: :column, table: "inquiries", column: "user_id")
  end

  it "rejects unknown keywords to keep" do
    expect { define { keep :inquiries, reason: "x", fro: 2.years } }.to raise_error(ArgumentError, /unknown keyword: fro/)
  end

  it "records ignore" do
    definition = define { ignore "audit_logs.admin_user_id", reason: "points at AdminUser" }

    expect(definition.policies.sole).to have_attributes(action: :ignore, reason: "points at AdminUser")
  end

  it "records one policy per attachment" do
    definition = define { destroy_attachments :avatar, :photos }

    expect(definition.policies.map(&:action).uniq).to eq([:destroy_attachment])
    expect(definition.policies.map(&:target)).to all(have_attributes(kind: :attachment))
    expect(definition.policies.map { |policy| policy.target.name }).to eq(%i[avatar photos])
  end

  it "records how the subject's own row goes" do
    line = __LINE__ + 1
    definition = define { subject soft_delete: :deleted_at, scrub: {email: nil} }

    expect(definition.subject_policy).to have_attributes(
      destroy: false, soft_delete: :deleted_at, scrub: {email: nil}, location: "#{__FILE__}:#{line}"
    )
  end

  it "needs at least one target" do
    expect { define { destroy } }.to raise_error(ArgumentError, /at least one target/)
    expect { define { destroy_attachments } }.to raise_error(ArgumentError, /at least one name/)
  end

  it "adds to an earlier definition of the same subject" do
    define { destroy :ratings }
    define { destroy :favorites }

    expect(Lethe.definitions.keys).to eq(["User"])
    expect(Lethe.definitions["User"].policies.map { |policy| policy.target.name }).to eq(%i[ratings favorites])
  end

  it "accepts the class itself" do
    user = model("User")
    Lethe.define(user) { destroy :ratings }

    expect(Lethe.definitions.keys).to eq(["User"])
  end

  it "needs a block and a named subject" do
    expect { Lethe.define("User") }.to raise_error(ArgumentError, /block/)
    expect { Lethe.define(Class.new) {} }.to raise_error(ArgumentError, /class name/)
    expect { Lethe.define("") {} }.to raise_error(ArgumentError, /class name/)
  end
end
