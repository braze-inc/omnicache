# frozen_string_literal: true

require_relative "entry"
require_relative "active_support_compatibility"
require_relative "datadog_tracing"

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
    # @param threadsafe [Boolean] Whether the store should be threadsafe
    # @param serializer [Object] Object that responds to `dump` and `load` for serialization. When max_size_bytes is
    #   set, the serializer must produce objects that respond to `bytesize`.
    # @param active_support_compatibility [Boolean] Whether to include ActiveSupport::Cache-compatible methods
    #   (read_multi, write_multi, fetch)
    # @param datadog_tracing [Boolean] Whether to wrap operations with Datadog tracing spans
    def initialize(
      default_ttl_seconds: nil,
      max_entries: nil,
      max_size_bytes: nil,
      threadsafe: true,
      serializer: Marshal,
      active_support_compatibility: false,
      datadog_tracing: false
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

      extend(ActiveSupportCompatibility) if active_support_compatibility
      extend(DatadogTracing) if datadog_tracing
    end

    # Reads a value from the store
    # @param key [String | Symbol] The key to read
    def read(key)
      maybe_threadsafe do
        entry = get_entry(key.to_s)
        if entry
          @serializer.load(entry.value)
        end
      end
    end

    alias [] read
    alias get read

    def write(key, value, ttl_seconds: nil)
      normalized_key = key.to_s
      maybe_threadsafe do
        delete_entry(normalized_key) if @is_lru || value.nil?
        entry = create_entry(normalized_key, value, ttl_seconds)
        adjust_size if @is_lru
        if entry
          value
        end
      end
    end

    alias []= write
    alias set write

    # Deletes a value from the store
    # @param key [String] The key to delete
    # @return [Object|nil] The deleted value if it existed, nil otherwise
    def delete(key)
      maybe_threadsafe do
        entry = delete_entry(key.to_s)
        if entry
          @serializer.load(entry.value)
        end
      end
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

    def get_entry(key)
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

    def create_entry(key, value, ttl_seconds)
      serialized_value = @serializer.dump(value)
      return nil if serialized_value.nil?

      entry = Entry.new(
        serialized_value,
        ttl_seconds: ttl_seconds || @default_ttl_seconds
      )

      @data[key] = entry
      add_size(key, entry)
      entry
    end

    def delete_entry(key)
      entry = @data.delete(key)
      subtract_size(key, entry)
      entry
    end
  end
end
