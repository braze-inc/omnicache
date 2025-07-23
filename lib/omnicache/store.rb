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
      with_tracing("read") do
        maybe_threadsafe do
          entry = get_entry(key.to_s)
          if entry
            @serializer.load(entry.value)
          end
        end
      end
    end

    alias [] read
    alias get read

    # Reads multiple values at once from the store
    # @param keys [Array<String>] The keys to read
    # @return [Hash] A hash mapping the keys provided to the values found
    def read_multi(*keys)
      with_tracing("read_multi") do
        results = maybe_threadsafe do
          keys.each_with_object({}) do |key, hash|
            entry = get_entry(key.to_s)
            if entry
              hash[key] = @serializer.load(entry.value)
            end
          end
        end
        results
      end
    end

    def write(key, value, ttl_seconds: nil)
      with_tracing("write") do
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
    end

    alias []= write
    alias set write

    # Writes multiple values at once to the store
    # @param entries [Hash] A hash mapping keys to values to write
    # @param ttl_seconds [Integer] TTL for the new entries, in seconds. Uses the default TTL if not provided.
    # @return [Hash] A hash mapping the keys provided to the values written
    def write_multi(entries, ttl_seconds: nil)
      with_tracing("write_multi") do
        results = maybe_threadsafe do
          written_entries = entries.each_with_object({}) do |(key, value), hash|
            normalized_key = key.to_s
            delete_entry(normalized_key) if @is_lru || value.nil?
            entry = create_entry(normalized_key, value, ttl_seconds)
            if entry
              hash[key] = value
            end
          end
          adjust_size if @is_lru
          written_entries
        end
        results
      end
    end

    # Reads a value from the store.
    # If it's not in the store, evaluate the given block and write the result to the store.
    #
    # @param key [String] The key to read
    # @param options [Hash] Optional options for the fetch operation
    # @option options [Integer] :expires_in The number of seconds until the cache entry expires
    # @option options [Time] :expires_at The time at which the cache entry expires
    # @yield The block to compute the value if the key is not found
    # @return The cached value or the result of the block if the key was not found
    def fetch(key, options = {})
      with_tracing("fetch") do
        ttl_seconds = nil

        if options.key?(:expires_in) && options.key?(:expires_at)
          raise ArgumentError, "Either :expires_in or :expires_at can be supplied, but not both"
        end

        if options[:expires_in]
          unless options[:expires_in].is_a?(Integer)
            raise ArgumentError, ":expires_in must be an Integer"
          end

          ttl_seconds = options[:expires_in]
        elsif options[:expires_at]
          unless options[:expires_at].is_a?(Time)
            raise ArgumentError, ":expires_at must be a Time"
          end

          ttl_seconds = options[:expires_at] - Time.now
        end

        read(key) || write(key, yield, ttl_seconds: ttl_seconds)
      end
    end

    # Deletes a value from the store
    # @param key [String] The key to delete
    # @return [Object|nil] The deleted value if it existed, nil otherwise
    def delete(key)
      with_tracing("delete") do
        maybe_threadsafe do
          entry = delete_entry(key.to_s)
          if entry
            @serializer.load(entry.value)
          end
        end
      end
    end

    def clear
      with_tracing("clear") do
        maybe_threadsafe do
          @data.clear
          @current_size_bytes = 0
        end
      end
    end

    def size
      @data.size
    end

    alias count size

    private

    def with_tracing(resource, &block)
      if defined?(Datadog::Tracing)
        Datadog::Tracing.trace(
          "omnicache",
          service: "omnicache",
          resource: resource,
          type: Datadog::Tracing::Metadata::Ext::AppTypes::TYPE_CACHE,
          &block
        )
      else
        yield(nil)
      end
    end

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
