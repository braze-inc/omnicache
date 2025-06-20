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

    it "can store and retrieve multiple values at once" do
      store.write_multi({ "key1" => "value1", "key2" => "value2" })
      expect(store.read_multi("key1", "key2")).to eq("key1" => "value1", "key2" => "value2")
    end

    it "can store and retrieve falsey values" do
      store.write("false-value", false)
      store.write("nil-value", nil)
      expect(store.read("false-value")).to be(false)
      expect(store.read("nil-value")).to be_nil
    end

    it "can store and retrieve multiple falsey values at once" do
      store.write_multi({ "false-value" => false, "nil-value" => nil })
      expect(store.read_multi("false-value", "nil-value")).to eq("false-value" => false, "nil-value" => nil)
    end

    it "coerces keys to strings" do
      store.write(123, "value")
      expect(store.read(123)).to eq("value")
      expect(store.read("123")).to eq("value")

      store.write_multi({ 456 => "value" })
      expect(store.read_multi(456)).to eq(456 => "value")
      expect(store.read_multi("456")).to eq("456" => "value")
    end

    it "returns nil if the key does not exist" do
      expect(store.read("key")).to be_nil
    end

    it "stores immutable values" do
      values = [1, 2, 3]
      store.write("key1", values)
      store.write_multi({ "key2" => values })
      values << 4
      expect(store.read_multi("key1", "key2")).to eq("key1" => [1, 2, 3], "key2" => [1, 2, 3])
    end

    it "does not return a value that has expired" do
      store.write("key", "value", ttl_seconds: 10)
      store.write_multi({ "key2" => "value2" }, ttl_seconds: 10)
      Timecop.freeze(Time.now + 20) do
        expect(store.read("key")).to be_nil
        expect(store.read_multi("key2")).to eq({})
      end
    end

    it "returns only existing keys when using read_multi" do
      store.write("key", "value")
      expect(store.read_multi("key", "key2")).to eq("key" => "value")
    end

    it "can delete a value from the store" do
      store.write("key", "value")
      expect(store.delete("key")).to eq("value")
      expect(store.read("key")).to be_nil
    end

    it "returns nil when deleting a non-existent key" do
      expect(store.delete("key")).to be_nil
    end

    it "returns results for read_multi with the given keys" do
      store.write_multi({ "key1" => "value1", "key2" => "value2" })
      expect(store.read_multi(:key1, "key2")).to eq({ key1: "value1", "key2" => "value2" })
    end

    it "returns write_multi results with the given keys" do
      expect(store.write_multi({ key1: "value1", "key2" => "value2" })).to eq({ key1: "value1", "key2" => "value2" })
    end
  end

  context "with a custom serializer" do
    let(:serializer) { identity_serializer }
    let(:store) { described_class.new(serializer: serializer) }

    it "uses that serializer" do
      values = [1, 2, 3]
      store.write("key1", values)
      store.write_multi({ "key2" => values })
      values << 4
      expect(store.read("key1")).to be(values)
      expect(store.read("key2")).to be(values)
    end
  end

  context "with max_entries set" do
    let(:store) { described_class.new(max_entries: 2) }

    describe "using #read & #write" do
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

    describe "using #read_multi & #write_multi" do
      it "evicts the least recently used entry when the size is exceeded" do
        store.write_multi({ "key1" => "value1", "key2" => "value2" })
        store.read_multi("key1")
        store.write_multi({ "key3" => "value3" })

        expect(store.size).to eq(2)
        expect(store.read_multi("key1", "key2", "key3")).to eq({ "key1" => "value1", "key3" => "value3" })
      end

      it "removes expired entries first before evicting others" do
        store.write_multi({ "key1" => "value1" }, ttl_seconds: 10)
        store.write_multi({ "key2" => "value2" })
        store.read_multi("key1")

        Timecop.freeze(Time.now + 20) do
          store.write_multi({ "key3" => "value3" })
        end

        expect(store.size).to eq(2)
        expect(store.read_multi("key1", "key2", "key3")).to eq({ "key2" => "value2", "key3" => "value3" })
      end
    end
  end

  context "with max_size_bytes set" do
    let(:store) { described_class.new(max_size_bytes: 20, serializer: string_serializer) }

    describe "using #read & #write" do
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
    end

    describe "using #read_multi & #write_multi" do
      it "evicts the least recently used entry when the size is exceeded" do
        store.write_multi({ "key1" => "value1", "key2" => "value2" })
        store.read_multi("key1")
        store.write_multi({ "key3" => "value3" })

        expect(store.size).to eq(2)
        expect(store.current_size_bytes).to eq(20)
        expect(store.read_multi("key1", "key2", "key3")).to eq({ "key1" => "value1", "key3" => "value3" })
      end

      it "removes expired entries first before evicting others" do
        store.write_multi({ "key1" => "value1" }, ttl_seconds: 10)
        store.write_multi({ "key2" => "value2" })
        store.read_multi("key1")

        Timecop.freeze(Time.now + 20) do
          store.write_multi({ "key3" => "value3" })
        end

        expect(store.size).to eq(2)
        expect(store.current_size_bytes).to eq(20)
        expect(store.read_multi("key1", "key2", "key3")).to eq({ "key2" => "value2", "key3" => "value3" })
      end
    end

    it "raises if the serializer does not produce objects that respond to :bytesize" do
      expect do
        described_class.new(max_size_bytes: 20, serializer: identity_serializer)
      end.to raise_error(/respond to :bytesize/)
    end

    it "updates current_size_bytes when a key is deleted" do
      expect { store.write("key", "value") }.to change(store, :current_size_bytes).to be > 0
      expect { store.delete("key") }.to change(store, :current_size_bytes).to(0)
    end
  end
end
