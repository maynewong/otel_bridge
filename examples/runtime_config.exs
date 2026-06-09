import Config

config :opentelemetry_experimental,
  readers: [
    # OTEL_EXPORTER_OTLP_METRICS_TIMEOUT and OTEL_EXPORTER_OTLP_TIMEOUT are
    # applied automatically by OtelBridge.Exporter.
    OtelBridge.metric_reader!(:victoria_metrics,
      export_interval_ms: 5_000,
      endpoint:
        System.get_env("OTEL_EXPORTER_OTLP_METRICS_ENDPOINT") ||
          System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT") ||
          "http://localhost:4318",
      protocol:
        case System.get_env("OTEL_EXPORTER_OTLP_PROTOCOL", "http/protobuf") do
          "grpc" -> :grpc
          _ -> :http_protobuf
        end
    )
  ]

config :opentelemetry,
  traces_exporter: :none,
  resource: %{
    service: %{
      name: System.get_env("OTEL_SERVICE_NAME", "example_app"),
      namespace: System.get_env("OTEL_SERVICE_NAMESPACE", "dev.example")
    }
  }
