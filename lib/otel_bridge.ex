defmodule OtelBridge do
  @moduledoc """
  Bridges existing `Telemetry.Metrics` definitions to OpenTelemetry metrics.

  `OtelBridge` is useful when an application already describes business metrics
  with `Telemetry.Metrics`, but wants to export them through the OpenTelemetry
  SDK without rewriting those metric definitions in another format.

  In practice, the bridge does three jobs:

    1. load metrics from one or more `OtelBridge.Spec` modules
    2. turn the supported `Telemetry.Metrics` definitions into OpenTelemetry instruments
    3. run any poller measurements and observer processes needed at runtime

  `OtelBridge` does not replace the OpenTelemetry SDK. Exporters, readers, and
  other SDK components are still configured through the standard OpenTelemetry
  packages. `OtelBridge` only handles the translation layer between
  `Telemetry.Metrics` and OpenTelemetry metrics.

  ## When to use it

  Use `OtelBridge` when:

    * your app already emits telemetry events and defines metrics with `Telemetry.Metrics`
    * you want to adopt OpenTelemetry metrics without rewriting existing metric definitions
    * you want to keep metric definitions in plain Elixir modules
    * you want backend-specific reader configuration to stay outside business code

  If you need tracing, logs, or full OpenTelemetry SDK setup, use the standard
  OpenTelemetry libraries alongside this project.

  ## How to use it

  A typical integration has three steps.

      MyApp.Metrics (OtelBridge.Spec)
                 |
                 v
             OtelBridge
           /           \
          v             v
      telemetry handlers  telemetry_poller
                 \       /
                  v     v
         OpenTelemetry metrics
                  |
                  v
         OtelBridge.Profile
                  |
                  v
            OTLP backend

  ### 1. Define a metric spec

  Create a module that uses `OtelBridge.Spec` and returns ordinary
  `Telemetry.Metrics` definitions:

      defmodule MyApp.Metrics do
        use OtelBridge.Spec

        @impl OtelBridge.Spec
        def metrics(meta) do
          [
            summary("http.server.duration",
              event_name: [:my_app, :http, :stop],
              measurement: :duration,
              unit: {:native, :millisecond},
              tags: [:route, :status_code],
              tag_values: fn metadata ->
                metadata
                |> Map.put(:route, metadata[:route] || "unknown")
                |> Map.put(:status_code, metadata[:status_code] || 500)
                |> Map.put(:service, Keyword.get(meta, :service))
              end
            )
          ]
        end
      end

  ### 2. Start `OtelBridge` in your supervision tree

      children = [
        {OtelBridge,
         specs: [MyApp.Metrics],
         measurements: [{MyApp.Measurements, :dispatch, []}],
         meta: [service: "my_app"],
         poller: [period: 5_000]}
      ]

  `OtelBridge` collects metrics from the provided spec modules, filters them
  down to the shapes the bridge supports, and starts the runtime processes that
  publish them.

  ### 3. Configure an OpenTelemetry metric reader

  Backend-specific reader helpers live in `OtelBridge.Profile` modules:

      config :opentelemetry_experimental,
        readers: [
          OtelBridge.metric_reader!(:victoria_metrics,
            export_interval_ms: 5_000,
            endpoint: "http://localhost:4318"
          )
        ]

  This keeps export policy separate from the metric definitions used by your
  application code.

  ## What gets mapped

  `OtelBridge` maps supported `Telemetry.Metrics` definitions to
  OpenTelemetry instruments at runtime:

    * `Telemetry.Metrics.Counter` -> counter
    * `Telemetry.Metrics.Sum` -> counter
    * `Telemetry.Metrics.Summary` -> histogram
    * `Telemetry.Metrics.Distribution` -> histogram

  During that process, the bridge groups metrics by event name, extracts the
  measurement value from telemetry events, applies any `keep` filter, derives
  tags through `tag_values`, and carries over unit, description, and explicit
  OTel reporter options.

  ## Runtime options

    * `:metrics` - raw `Telemetry.Metrics` definitions to load directly
    * `:specs` - metric spec modules implementing `OtelBridge.Spec`
    * `:optional_specs` - spec modules to load only when available
    * `:measurements` - `:telemetry_poller` measurement entries
    * `:meta` - keyword metadata passed to each spec module
    * `:poller` - `:telemetry_poller` options such as polling period
    * `:observer_children` - extra children for gauge-like or observable metrics

  Metrics such as `Telemetry.Metrics.LastValue` are intentionally left out of
  the default bridge path and should be handled with observers or custom
  runtime logic.
  """

  @typedoc """
  Runtime option accepted by `start_link/1` and `child_spec/1`.
  """
  @type option ::
          {:metrics, [Telemetry.Metrics.t()]}
          | {:specs, [module()]}
          | {:optional_specs, [module()]}
          | {:measurements, [module() | {module(), atom(), [term()]}]}
          | {:meta, keyword()}
          | {:poller, keyword()}
          | {:observer_children, [Supervisor.child_spec()]}

  @doc """
  Starts the `OtelBridge` supervision tree.

  This is the main entrypoint most applications should use when adding the
  bridge to a supervision tree.
  """
  @spec start_link([option()]) :: Supervisor.on_start()
  def start_link(opts) do
    opts
    |> normalize_opts()
    |> OtelBridge.Supervisor.start_link()
  end

  @doc """
  Returns a standard supervisor child spec for `OtelBridge`.
  """
  @spec child_spec([option()]) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}
  end

  @doc """
  Filters a list of `Telemetry.Metrics` definitions down to the metric shapes
  handled by the bridge runtime.

  Today this excludes shapes such as `Telemetry.Metrics.LastValue`, which are
  expected to be implemented through observers or custom handling.
  """
  @spec prepare_metrics([Telemetry.Metrics.t()]) :: [Telemetry.Metrics.t()]
  def prepare_metrics(metrics) do
    OtelBridge.Supervisor.prepare_metrics(metrics)
  end

  @doc """
  Builds a metric reader config from a named or module-based backend profile.

  Use this when you want to keep exporter-specific policy in an
  `OtelBridge.Profile` module instead of hardcoding reader maps in application
  config.
  """
  @spec metric_reader!(OtelBridge.Profile.profile_ref(), keyword()) :: map()
  def metric_reader!(profile, opts) do
    OtelBridge.Profile.metric_reader!(profile, opts)
  end

  defp normalize_opts(opts) do
    opts
    |> Keyword.put_new(:metrics, [])
    |> Keyword.put_new(:specs, [])
    |> Keyword.put_new(:optional_specs, [])
    |> Keyword.put_new(:measurements, [])
    |> Keyword.put_new(:meta, [])
    |> Keyword.put_new(:poller, period: 5_000)
    |> Keyword.put_new(:observer_children, [])
  end
end
