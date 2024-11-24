# frozen_string_literal: true

RSpec.describe OmniCache::Store do
  let(:identity_serializer) do
    Class.new do
      def self.dump(value)
        value
      end

      def self.load(value)
        value
      end
    end
  end
  let(:string_serializer) do
    Class.new do
      def self.dump(value)
        value.to_s
      end

      def self.load(value)
        value
      end
    end
  end

  context "with the default configuration" do
    let(:store) { described_class.new }

    it "can store and retrieve a value" do
      store.write("key", "value")
      expect(store.read("key")).to eq("value")
    end

    it "coerces keys to strings" do
      store.write(123, "value")
      expect(store.read(123)).to eq("value")
      expect(store.read("123")).to eq("value")
    end

    it "returns nil if the key does not exist" do
      expect(store.read("key")).to be_nil
    end

    it "stores immutable values" do
      values = [1, 2, 3]
      store.write("key", values)
      values << 4
      expect(store.read("key")).to eq([1, 2, 3])
    end

    it "does not return a value that has expired" do
      store.write("key", "value", ttl_seconds: 10)
      Timecop.freeze(Time.now + 20) do
        expect(store.read("key")).to be_nil
      end
    end
  end

  context "with a custom serializer" do
    let(:serializer) { identity_serializer }
    let(:store) { described_class.new(serializer: serializer) }

    it "uses that serializer" do
      values = [1, 2, 3]
      store.write("key", values)
      values << 4
      expect(store.read("key")).to eq([1, 2, 3, 4])
    end
  end

  context "with max_entries set" do
    let(:store) { described_class.new(max_entries: 2) }

    it "evicts the least recently used entry when the size is exceeded" do
      store.write("key1", "value1")
      store.write("key2", "value2")
      store.read("key1")
      store.write("key3", "value3")

      expect(store.size).to eq(2)
      expect(store.read("key1")).to eq("value1")
      expect(store.read("key3")).to eq("value3")
      expect(store.read("key2")).to be_nil
    end

    it "removes expired entries first before evicting others" do
      store.write("key1", "value1", ttl_seconds: 10)
      store.write("key2", "value2")
      store.read("key1")

      Timecop.freeze(Time.now + 20) do
        store.write("key3", "value3")
      end

      expect(store.size).to eq(2)
      expect(store.read("key2")).to eq("value2")
      expect(store.read("key3")).to eq("value3")
      expect(store.read("key1")).to be_nil
    end
  end

  context "with max_size_bytes set" do
    let(:store) { described_class.new(max_size_bytes: 20, serializer: string_serializer) }

    it "evicts the least recently used entry when the size is exceeded" do
      store.write("key1", "value1")
      store.write("key2", "value2")
      store.read("key1")
      store.write("key3", "value3")

      expect(store.size).to eq(2)
      expect(store.current_size_bytes).to eq(20)
      expect(store.read("key1")).to eq("value1")
      expect(store.read("key3")).to eq("value3")
      expect(store.read("key2")).to be_nil
    end

    it "removes expired entries first before evicting others" do
      store.write("key1", "value1", ttl_seconds: 10)
      store.write("key2", "value2")
      store.read("key1")

      Timecop.freeze(Time.now + 20) do
        store.write("key3", "value3")
      end

      expect(store.size).to eq(2)
      expect(store.current_size_bytes).to eq(20)
      expect(store.read("key2")).to eq("value2")
      expect(store.read("key3")).to eq("value3")
      expect(store.read("key1")).to be_nil
    end

    it "raises if the serializer does not produce objects that respond to :bytesize" do
      expect do
        described_class.new(max_size_bytes: 20, serializer: identity_serializer)
      end.to raise_error(/respond to :bytesize/)
    end
  end
end
