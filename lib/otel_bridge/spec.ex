defmodule OtelBridge.Spec do
  @moduledoc """
  Defines the modules that declare application metrics for `OtelBridge`.

  A spec module declares metrics in plain `Telemetry.Metrics` terms while
  leaving OpenTelemetry runtime concerns to `OtelBridge`.

  ## A minimal example

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

  Pass modules like this to `OtelBridge` through the `:specs` option.

  ## About `meta`

  The `meta` argument is provided by the `:meta` option passed to `OtelBridge`.
  Use it for values that should be shared across metric definitions, such as:

    * service name
    * environment name
    * static tags
    * reusable defaults
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
