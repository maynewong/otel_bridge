defmodule OtelBridge do
  @moduledoc """
  Bridges `Telemetry.Metrics` definitions into OpenTelemetry metrics.

  The public API stays intentionally small:

    * callers define metric spec modules implementing `OtelBridge.Spec`
    * callers optionally attach observer children for gauge-like metrics
    * backend policy is selected via `OtelBridge.Profile` modules
  """

  @type option ::
          {:metrics, [Telemetry.Metrics.t()]}
          | {:specs, [module()]}
          | {:optional_specs, [module()]}
          | {:measurements, [module() | {module(), atom(), [term()]}]}
          | {:meta, keyword()}
          | {:poller, keyword()}
          | {:observer_children, [Supervisor.child_spec()]}

  @spec start_link([option()]) :: Supervisor.on_start()
  def start_link(opts) do
    opts
    |> normalize_opts()
    |> OtelBridge.Supervisor.start_link()
  end

  @spec child_spec([option()]) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}
  end

  @spec prepare_metrics([Telemetry.Metrics.t()]) :: [Telemetry.Metrics.t()]
  def prepare_metrics(metrics) do
    OtelBridge.Supervisor.prepare_metrics(metrics)
  end

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
