defmodule OtelBridge.Supervisor do
  @moduledoc """
  Internal supervisor that assembles the `otel_bridge` runtime.

  Applications typically start `OtelBridge` instead of this module directly.

  It coordinates:

    1. metric definitions loaded from specs or raw metric lists
    2. the `OtelBridge.Bridge` process that attaches telemetry handlers
    3. the `:telemetry_poller` process for periodic measurements
  """

  use Supervisor

  @doc """
  Starts the bridge supervisor.
  """
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts)
  end

  @impl Supervisor
  def init(opts) do
    metrics_config = build_metrics_config(opts)
    observer_children = Keyword.get(opts, :observer_children, [])

    children =
      [
        {OtelBridge.Bridge, metrics: prepare_metrics(load_metrics(opts, metrics_config))}
      ] ++
        observer_children ++
        [
          {:telemetry_poller,
           Keyword.merge([measurements: metrics_config[:measurements]], metrics_config[:poller])}
        ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Filters out metric shapes that the bridge intentionally leaves to observable
  instruments or custom handling.

  For example, `Telemetry.Metrics.LastValue` is excluded from the default
  runtime path because it usually needs observer-style behavior rather than the
  synchronous event-to-instrument flow used by this bridge.
  """
  def prepare_metrics(metrics) do
    Enum.reject(metrics, &match?(%Telemetry.Metrics.LastValue{}, &1))
  end

  defp load_metrics(opts, metrics_config) do
    specs =
      opts
      |> Keyword.get(:specs, [])
      |> Kernel.++(load_optional_specs(Keyword.get(opts, :optional_specs, [])))

    spec_metrics =
      Enum.flat_map(specs, fn module ->
        module.metrics(metrics_config[:meta])
      end)

    Keyword.get(opts, :metrics, []) ++ spec_metrics
  end

  defp load_optional_specs(optional_specs) do
    Enum.filter(optional_specs, fn module ->
      Code.ensure_loaded?(module) && function_exported?(module, :metrics, 1)
    end)
  end

  defp build_metrics_config(opts) do
    [
      meta: Keyword.get(opts, :meta, []),
      measurements: Keyword.get(opts, :measurements, []),
      poller: Keyword.get(opts, :poller, period: 5_000)
    ]
  end
end
