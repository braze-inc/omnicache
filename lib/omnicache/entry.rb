# frozen_string_literal: true

module OmniCache
  # Represents a single cache entry, with an optional TTL.
  class Entry
    attr_reader :value, :expires_at

    def initialize(value, ttl_seconds: nil)
      @value = value
      @expires_at = ttl_seconds ? Time.now + ttl_seconds : nil
    end

    def expired?
      expires_at && @expires_at < Time.now
    end
  end
end
