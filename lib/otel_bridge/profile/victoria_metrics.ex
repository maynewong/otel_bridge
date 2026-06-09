defmodule OtelBridge.Profile.VictoriaMetrics do
  @moduledoc """
  Built-in export profile for VictoriaMetrics.

  Use this profile when you want `otel_bridge` to emit metrics through an OTLP
  metric reader configured for VictoriaMetrics-compatible workflows.

  This profile configures cumulative temporality for synchronous counters and
  histograms to align with VictoriaMetrics and Prometheus-style query
  expectations.

  For HTTP protobuf exports, the profile supports `:timeout_ms` and
  `:connect_timeout_ms`. Standard OTLP timeout environment variables are applied
  by `OtelBridge.Exporter` and take precedence over profile options.

  ## Typical usage

      config :opentelemetry_experimental,
        readers: [
          OtelBridge.metric_reader!(:victoria_metrics,
            export_interval_ms: 5_000,
            endpoint: "http://localhost:4318"
          )
        ]

  If you need different backend behavior, create another
  `OtelBridge.Profile` implementation instead of changing business metric
  definitions.
  """

  @behaviour OtelBridge.Profile

  @default_temporality_mapping %{
    counter: :temporality_cumulative,
    histogram: :temporality_cumulative,
    updown_counter: :temporality_cumulative
  }

  @impl OtelBridge.Profile
  @doc """
  Builds an `:otel_metric_reader` configuration for VictoriaMetrics.

  Required options:

    * `:export_interval_ms`
    * `:endpoint`

  Optional options:

    * `:protocol` - defaults to `:http_protobuf`
    * `:timeout_ms` - HTTP export timeout; defaults to the OTLP standard of
      `10_000`, and `0` means no limit
    * `:connect_timeout_ms` - defaults to `5_000`, capped by `:timeout_ms`; a
      no-limit OTLP timeout also removes the default connection limit
  """
  def metric_reader(opts) do
    export_interval_ms = Keyword.fetch!(opts, :export_interval_ms)
    endpoint = Keyword.fetch!(opts, :endpoint)
    protocol = Keyword.get(opts, :protocol, :http_protobuf)

    exporter_opts =
      %{endpoints: [endpoint], protocol: protocol}
      |> Map.merge(Map.new(Keyword.take(opts, [:timeout_ms, :connect_timeout_ms])))

    %{
      module: :otel_metric_reader,
      config: %{
        export_interval_ms: export_interval_ms,
        default_temporality_mapping: @default_temporality_mapping,
        exporter: {OtelBridge.Exporter, exporter_opts}
      }
    }
  end

  @doc """
  Returns the synchronous temporality defaults used by this profile.
  """
  def default_temporality_mapping, do: @default_temporality_mapping
end
