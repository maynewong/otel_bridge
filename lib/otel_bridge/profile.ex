defmodule OtelBridge.Profile do
  @moduledoc false

  @callback metric_reader(keyword()) :: map()

  @type profile_name :: :victoria_metrics
  @type profile_ref :: profile_name() | module()

  @spec metric_reader!(profile_ref(), keyword()) :: map()
  def metric_reader!(profile, opts) do
    module = resolve!(profile)

    module.metric_reader(opts)
  end

  @spec resolve!(profile_ref()) :: module()
  def resolve!(:victoria_metrics), do: OtelBridge.Profile.VictoriaMetrics
  def resolve!(module) when is_atom(module), do: module
end
