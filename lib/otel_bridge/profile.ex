defmodule OtelBridge.Profile do
  @moduledoc """
  Defines backend-specific metric reader configuration for `OtelBridge`.

  `OtelBridge.Profile` exists so application metric definitions can stay
  backend-agnostic.

  A profile takes a backend choice such as VictoriaMetrics and turns it into
  the metric reader configuration expected by `:opentelemetry_experimental`.
  This keeps export details out of business modules and out of most call sites.

  ## When you need this module

  Use a profile when:

    * you want a named helper such as `:victoria_metrics`
    * you want a reusable module that builds a metric reader map
    * you want backend-specific defaults to live in one place

  If you do not need a profile abstraction, you can configure the
  OpenTelemetry SDK directly and use `otel_bridge` only for metrics bridging.

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
