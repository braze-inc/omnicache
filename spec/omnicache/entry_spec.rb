# frozen_string_literal: true

RSpec.describe OmniCache::Entry do
  describe "#expired?" do
    let!(:now) { Time.now }
    let!(:entry) { described_class.new("value", ttl_seconds: 60) }

    it "returns false when no TTL is provided" do
      expect(entry.expired?).to be false
    end

    it "returns false when the TTL has not elapsed" do
      Timecop.freeze(now + 60) do
        expect(entry.expired?).to be false
      end
    end

    it "returns true when the TTL has elapsed" do
      Timecop.freeze(now + 61) do
        expect(entry.expired?).to be true
      end
    end
  end
end
