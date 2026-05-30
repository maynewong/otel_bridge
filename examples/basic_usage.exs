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
      )
    ]
  end
end

children = [
  {OtelBridge,
   specs: [ExampleApp.Metrics],
   measurements: [],
   meta: [service: "example_app"],
   poller: [period: 5_000]}
]
