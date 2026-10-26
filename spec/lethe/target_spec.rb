# frozen_string_literal: true

RSpec.describe Lethe::Target do
  describe ".parse" do
    it "reads a symbol as an association of the subject" do
      target = described_class.parse(:ratings)
      expect(target).to have_attributes(kind: :association, name: :ratings, table: nil, column: nil)
      expect(target.to_s).to eq(":ratings")
    end

    it "reads \"table.column\" as a column" do
      target = described_class.parse("follows.following_id")
      expect(target).to have_attributes(kind: :column, table: "follows", column: "following_id")
      expect(target.to_s).to eq("follows.following_id")
    end

    ["follows", "follows.", ".user_id", "a.b.c", ""].each do |value|
      it "rejects #{value.inspect}" do
        expect { described_class.parse(value) }.to raise_error(ArgumentError, /table\.column/)
      end
    end

    it "rejects anything that is not a symbol or a string" do
      expect { described_class.parse(Object) }.to raise_error(ArgumentError, /association name/)
    end
  end

  describe ".attachment" do
    it "reads a symbol as an attachment" do
      target = described_class.attachment(:avatar)
      expect(target).to have_attributes(kind: :attachment, name: :avatar)
      expect(target.to_s).to eq("attachment :avatar")
    end

    it "rejects a string" do
      expect { described_class.attachment("avatar") }.to raise_error(ArgumentError, /Symbol/)
    end
  end
end
