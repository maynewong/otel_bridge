defmodule OtelBridge.Profile do
  @moduledoc """
  Behaviour and helpers for backend-specific metric export profiles.

  A profile turns high-level backend intent into a metric reader configuration
  suitable for `:opentelemetry_experimental`.

  ## Example

      config :opentelemetry_experimental,
        readers: [
          OtelBridge.metric_reader!(:victoria_metrics,
            export_interval_ms: 5_000,
            endpoint: "http://localhost:4318"
          )
        ]
  """

  @doc """
  Builds a metric reader configuration for a backend profile.
  """
  @callback metric_reader(keyword()) :: map()

  @type profile_name :: :victoria_metrics
  @type profile_ref :: profile_name() | module()

  @doc """
  Resolves a profile name or module and returns its metric reader config.
  """
  @spec metric_reader!(profile_ref(), keyword()) :: map()
  def metric_reader!(profile, opts) do
    module = resolve!(profile)

    module.metric_reader(opts)
  end

  @doc """
  Resolves a profile alias to its implementing module.
  """
  @spec resolve!(profile_ref()) :: module()
  def resolve!(:victoria_metrics), do: OtelBridge.Profile.VictoriaMetrics
  def resolve!(module) when is_atom(module), do: module
end
