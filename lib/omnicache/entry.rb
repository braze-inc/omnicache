# frozen_string_literal: true

module OmniCache
  # Represents a single cache entry, with an optional TTL.
  class Entry
    attr_reader :value, :expires_at

    def initialize(value, expires_in: nil)
      @value = value
      @expires_at = expires_in ? Time.now + expires_in : nil
    end

    def expired?
      expires_at && @expires_at < Time.now
    end
  end
end
