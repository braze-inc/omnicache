# frozen_string_literal: true

require_relative "entry"

module OmniCache
  class Store # :nodoc:
    attr_reader :default_ttl_seconds, :max_entries, :max_size_bytes, :current_size_bytes, :threadsafe, :serializer

    # Creates a new OmniCache store. All arguments are optional.
    #
    # @param default_ttl_seconds [Integer] Default TTL for entries, in seconds
    # @param max_entries [Integer] Maximum number of entries to store. If exceeded, the store will evict the least
    #   recently used entries.
    # @param max_size_bytes [Integer] Maximum size of all entries in bytes. If exceeded, the store will evict the least
    #   recently used entries. The size of an entry is the bytesize of its serialized value. The key is not included.
    # @params threadsafe [Boolean] Whether the store should be threadsafe
    # @param serializer [Object] Object that responds to `dump` and `load` for serialization. When max_size_bytes is
    #   set, the serializer must produce objects that respond to `bytesize`.
    def initialize(
      default_ttl_seconds: nil,
      max_entries: nil,
      max_size_bytes: nil,
      threadsafe: true,
      serializer: Marshal
    )
      @default_ttl_seconds = default_ttl_seconds
      @max_entries = max_entries
      @max_size_bytes = max_size_bytes
      @threadsafe = threadsafe
      @serializer = serializer

      @is_lru = !(max_entries || max_size_bytes).nil?
      @current_size_bytes = 0

      @mutex = threadsafe ? Mutex.new : nil

      @data = {}

      check_serializer
    end

    # Reads a value from the store
    # @param key [String | Symbol] The key to read
    def read(key)
      key = key.to_s
      entry = maybe_threadsafe do
        entry = @is_lru ? @data.delete(key) : @data[key]
        return nil if entry.nil?

        if entry.expired?
          @data.delete(key) unless @is_lru # we already deleted it if LRU
          subtract_size(key, entry)
          return nil
        end

        @data[key] = entry if @is_lru
        entry
      end

      @serializer.load(entry.value)
    end

    alias [] read
    alias get read

    def write(key, value, ttl_seconds: nil)
      key = key.to_s
      maybe_threadsafe do
        if @is_lru || value.nil?
          existing = @data.delete(key)
          subtract_size(key, existing)
        end

        serialized_value = @serializer.dump(value)
        return nil if serialized_value.nil?

        entry = Entry.new(
          serialized_value,
          ttl_seconds: ttl_seconds || @default_ttl_seconds
        )

        @data[key] = entry
        add_size(key, entry)

        adjust_size if @is_lru
      end
      value
    end

    alias []= write
    alias set write

    def fetch(key, ttl_seconds: nil)
      read(key) || write(key, yield, ttl_seconds: ttl_seconds)
    end

    def clear
      maybe_threadsafe do
        @data.clear
        @current_size_bytes = 0
      end
    end

    def size
      @data.size
    end

    alias count size

    private

    def check_serializer
      return unless @max_size_bytes

      test = @serializer.dump(Object.new)
      return if test.respond_to?(:bytesize)

      raise "When used with max_size_bytes, the serializer must produce objects that respond to :bytesize"
    end

    def add_size(key, entry)
      return unless entry && @max_size_bytes

      @current_size_bytes += (key.to_s.bytesize + entry.value.bytesize)
    end

    def subtract_size(key, entry)
      return unless entry && @max_size_bytes

      @current_size_bytes -= (key.to_s.bytesize + entry.value.bytesize)
    end

    def adjust_size
      trim_to_max_bytes = @max_size_bytes && @current_size_bytes > @max_size_bytes
      trim_to_max_entries = @max_entries && @data.size > @max_entries

      return unless trim_to_max_bytes || trim_to_max_entries

      # first, remove expired entries
      @data.delete_if do |key, entry|
        if entry.expired?
          subtract_size(key, entry)
          true
        end
      end

      while @max_size_bytes && @current_size_bytes > @max_size_bytes
        key, entry = @data.shift
        subtract_size(key, entry)
      end

      while @max_entries && @data.size > @max_entries
        key, entry = @data.shift
        subtract_size(key, entry)
      end
    end

    def maybe_threadsafe(&block)
      if @mutex
        @mutex.synchronize(&block)
      else
        yield
      end
    end
  end
end
