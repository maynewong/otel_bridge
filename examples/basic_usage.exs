defmodule ExampleApp.Metrics do
  use OtelBridge.Spec

  @impl OtelBridge.Spec
  def metrics(meta) do
    [
      summary("example.http.duration",
        event_name: [:example_app, :http, :stop],
        measurement: :duration,
        unit: {:native, :millisecond},
        tags: [:route, :status_code],
        tag_values: fn metadata ->
          metadata
          |> Map.put(:route, metadata[:route] || "unknown")
          |> Map.put(:status_code, metadata[:status_code] || 500)
          |> Map.put(:service, Keyword.fetch!(meta, :service))
        end
      ),
      counter("example.http.requests",
        event_name: [:example_app, :http, :stop],
        tags: [:route, :status_code],
        tag_values: fn metadata ->
          metadata
          |> Map.put(:route, metadata[:route] || "unknown")
          |> Map.put(:status_code, metadata[:status_code] || 500)
        end
      ),
      last_value("example.queue.depth",
        event_name: [:example_app, :queue, :stats],
        measurement: :depth,
        tags: [:queue],
        reporter_options: [
          otel: [
            last_value: [
              ttl_ms: 300_000,
              max_series: 100,
              on_overflow: :drop_new
            ]
          ]
        ]
      )
    ]
  end
end

defmodule ExampleApp.Measurements do
  def dispatch_queue_depth do
    :telemetry.execute(
      [:example_app, :queue, :stats],
      %{depth: 42},
      %{queue: "default"}
    )
  end
end

children = [
  {OtelBridge,
   specs: [ExampleApp.Metrics],
   measurements: [{ExampleApp.Measurements, :dispatch_queue_depth, []}],
   meta: [service: "example_app"],
   poller: [period: 5_000]}
]
