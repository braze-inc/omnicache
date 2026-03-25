# frozen_string_literal: true

module OmniCache
  module DatadogTracing
    def read(key)
      with_tracing("read") { super }
    end

    def write(key, value, ttl_seconds: nil)
      with_tracing("write") { super }
    end

    def read_multi(*keys)
      with_tracing("read_multi") { super }
    end

    def write_multi(entries, ttl_seconds: nil)
      with_tracing("write_multi") { super }
    end

    def fetch(key, options = {}, &block)
      with_tracing("fetch") { super }
    end

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
  end
end
