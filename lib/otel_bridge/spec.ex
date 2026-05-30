defmodule OtelBridge.Spec do
  @moduledoc """
  Behaviour for metric specification modules consumed by `OtelBridge`.

  A spec module defines metric metadata in plain `Telemetry.Metrics` terms while
  leaving OpenTelemetry instrument creation and backend policy to the bridge.

  ## Example

      defmodule MyApp.Metrics do
        use OtelBridge.Spec

        @impl OtelBridge.Spec
        def metrics(meta) do
          [
            summary("my_app.request.duration",
              event_name: [:my_app, :request, :stop],
              measurement: :duration,
              unit: {:native, :millisecond},
              tags: [:route],
              tag_values: fn metadata ->
                Map.put(metadata, :route, Keyword.get(meta, :default_route, "unknown"))
              end
            )
          ]
        end
      end
  """

  @doc """
  Returns the `Telemetry.Metrics` definitions for the caller.

  The `meta` argument is passed from the `:meta` option given to `OtelBridge`.
  Use it for shared configuration such as service names, static tags, or
  reusable defaults.
  """
  @callback metrics(keyword()) :: [Telemetry.Metrics.t()]

  @doc """
  Imports `Telemetry.Metrics` helpers and marks the module as an
  `OtelBridge.Spec`.
  """
  defmacro __using__(_opts) do
    quote do
      import Telemetry.Metrics

      @behaviour OtelBridge.Spec
    end
  end
end
