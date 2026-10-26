# frozen_string_literal: true

RSpec.describe "enums in where: and set:" do
  before do
    schema do
      create_table(:users) do |t|
        t.integer :plan, default: 0
        t.datetime :deleted_at
      end
      create_table(:questions) do |t|
        t.references :user, foreign_key: true
        t.integer :status, null: false
        t.string :visibility, null: false, default: "public"
        t.text :body
      end
    end
    model("Question") do
      belongs_to :user
      enum :status, {pending: 0, answered: 1, declined: 2}
      enum :visibility, {everyone: "public", followers: "private"}
    end
    model("User") do
      has_many :questions
      enum :plan, {free: 0, premium: 1, closed: 2}
    end
  end

  let(:models) { [Question, User] }
  let!(:alice) { User.create!(plan: :premium) }
  let!(:bob) { User.create!(plan: :premium) }

  before do
    [alice, bob].each do |user|
      Question.create!(user: user, status: :answered, body: "kept, emptied", visibility: :everyone)
      Question.create!(user: user, status: :pending, body: "deleted", visibility: :everyone)
      Question.create!(user: user, status: :declined, body: "deleted", visibility: :everyone)
    end
  end

  def define(where_answered: "answered", deleted: %w[pending declined])
    Lethe.define("User") do
      subject soft_delete: :deleted_at, scrub: {plan: "closed"}
      scrub :questions, where: {status: where_answered}, set: {body: "", visibility: :followers}
      destroy :questions, where: {status: deleted}
    end
  end

  it "erases by enum name, as the model would read it" do
    define

    erasure = Lethe.erase!(alice, models: models)

    expect(erasure.counts["questions.user_id"]).to eq("scrub" => 1, "destroy" => 2)
    expect(Question.where(user: alice).pluck(:status, :body, :visibility)).to eq([["answered", "", "followers"]])
    expect(User.find(alice.id).plan).to eq("closed")
    expect(Question.where(user: bob).count).to eq(3)
    expect(Lethe.leftovers(alice, models: models)).to eq([])
  end

  it "accepts stored values and symbols too" do
    define(where_answered: 1, deleted: [:pending, 2])

    Lethe.erase!(alice, models: models)

    expect(Question.where(user: alice).pluck(:status)).to eq(["answered"])
  end

  it "reports a name the enum does not have, instead of matching nothing" do
    define(where_answered: "anwsered")

    report = check(models)
    result = report.results.find { |each| each.status == :invalid }
    expect(result.message).to eq(["unknown_enum_value", {option: "where", table: "questions", column: "status", value: '"anwsered"'}])
    expect { Lethe.erase!(alice, models: models) }.to raise_error(Lethe::Unclean, /"anwsered" is not a value of the status enum on questions/)
  end

  it "reports a set: or subject scrub: value the enum does not have" do
    Lethe.define("User") do
      subject soft_delete: :deleted_at, scrub: {plan: "gone"}
      scrub :questions, set: {visibility: "secret"}
    end

    messages = check(models).results.select { |result| result.status == :invalid }.map(&:message)
    expect(messages).to contain_exactly(
      ["unknown_enum_value", {option: "set", table: "questions", column: "visibility", value: '"secret"'}],
      ["unknown_enum_value", {option: "scrub", table: "users", column: "plan", value: '"gone"'}]
    )
  end

  it "finds what an erasure missed by enum name" do
    define
    Lethe.erase!(alice, models: models)
    Question.create!(user: alice, status: :pending, body: "late")
    Question.where(user: alice, status: :answered).update_all(visibility: "public")

    expect(Lethe.leftovers(alice, models: models).map(&:to_s)).to eq([
      "questions.user_id: 1 not deleted",
      "questions.user_id: 1 not scrubbed"
    ])
  end

  describe Lethe::Enums do
    it "leaves hashes alone without a model or an enum" do
      expect(described_class.cast(nil, {status: "answered"})).to eq(status: "answered")
      expect(described_class.cast(Question, {body: "answered"})).to eq(body: "answered")
      expect(described_class.cast(Question, nil)).to be_nil
      expect(described_class.unknown(nil, {status: "x"})).to eq([])
      expect(described_class.unknown(Question, nil)).to eq([])
    end

    it "ignores nil and Procs when looking for unknown values" do
      expect(described_class.unknown(Question, {status: [nil, -> {}], visibility: "public"})).to eq([])
    end
  end
end
