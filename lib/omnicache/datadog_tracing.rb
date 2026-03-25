# frozen_string_literal: true

module OmniCache
  # Wraps Store read and write operations with Datadog tracing spans.
  module DatadogTracing
    def read(key)
      with_tracing("read", key: key) { super }
    end

    def write(key, value, *args)
      with_tracing("write", key: key) { super }
    end

    def read_multi(*keys)
      with_tracing("read_multi", key: keys.join(", ")) { super }
    end

    def write_multi(entries, *args)
      with_tracing("write_multi", key: entries.keys.join(", ")) { super }
    end

    def fetch(key, *args, &block)
      with_tracing("fetch", key: key) { super }
    end

    private

    def with_tracing(resource, key: nil, &block)
      if defined?(Datadog::Tracing)
        Datadog::Tracing.trace(
          "omnicache",
          service: "omnicache",
          resource: resource,
          tags: { key: key.to_s[...250] },
          type: Datadog::Tracing::Metadata::Ext::AppTypes::TYPE_CACHE,
          &block
        )
      else
        yield(nil)
      end
    end
  end
end
