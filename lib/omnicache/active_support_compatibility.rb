# frozen_string_literal: true

module OmniCache
  # Provides ActiveSupport::Cache-compatible methods (read_multi, write_multi, fetch).
  module ActiveSupportCompatibility
    # Writes a value to the store using ActiveSupport-compatible options.
    #
    # @param key [String | Symbol] The key to write
    # @param value [Object] The value to write
    # @param options [Hash] Options hash
    # @option options [Integer] :expires_in Number of seconds until the entry expires
    # @option options [Time] :expires_at Time at which the entry expires
    def write(key, value, options = {})
      super(key, value, ttl_seconds: ttl_from_options(options))
    end

    # Reads multiple values at once from the store
    # @param keys [Array<String>] The keys to read
    # @return [Hash] A hash mapping the keys provided to the values found
    def read_multi(*keys)
      maybe_threadsafe do
        keys.each_with_object({}) do |key, hash|
          entry = get_entry(key.to_s)
          if entry
            hash[key] = @serializer.load(entry.value)
          end
        end
      end
    end

    # Writes multiple values at once to the store
    # @param entries [Hash] A hash mapping keys to values to write
    # @param options [Hash] Options hash
    # @option options [Integer] :expires_in Number of seconds until the entries expire
    # @return [Hash] A hash mapping the keys provided to the values written
    def write_multi(entries, options = {})
      ttl_seconds = ttl_from_options(options)
      maybe_threadsafe do
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
    end

    # Reads a value from the store.
    # If it's not in the store, evaluate the given block and write the result to the store.
    #
    # @param key [String] The key to read
    # @param options [Hash] Options hash
    # @option options [Integer] :expires_in Number of seconds until the entry expires
    # @option options [Time] :expires_at Time at which the entry expires
    # @yield The block to compute the value if the key is not found
    # @return The cached value or the result of the block if the key was not found
    def fetch(key, options = {})
      read(key) || write(key, yield, options)
    end

    private

    def ttl_from_options(options)
      if options.key?(:expires_in) && options.key?(:expires_at)
        raise ArgumentError, "Either :expires_in or :expires_at can be supplied, but not both"
      end

      if options[:expires_in]
        raise ArgumentError, ":expires_in must be an Integer" unless options[:expires_in].is_a?(Integer)

        options[:expires_in]
      elsif options[:expires_at]
        raise ArgumentError, ":expires_at must be a Time" unless options[:expires_at].is_a?(Time)

        options[:expires_at] - Time.now
      end
    end
  end
end
