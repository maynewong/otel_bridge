defmodule OtelBridge.Profile.VictoriaMetrics do
  @moduledoc """
  VictoriaMetrics-oriented metric reader profile.

  This profile keeps synchronous counters and histograms cumulative because
  that shape is commonly easier to consume in VictoriaMetrics and
  Prometheus-style queries.
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
  """
  def metric_reader(opts) do
    export_interval_ms = Keyword.fetch!(opts, :export_interval_ms)
    endpoint = Keyword.fetch!(opts, :endpoint)
    protocol = Keyword.get(opts, :protocol, :http_protobuf)

    %{
      module: :otel_metric_reader,
      config: %{
        export_interval_ms: export_interval_ms,
        default_temporality_mapping: @default_temporality_mapping,
        exporter:
          {OtelBridge.Exporter,
           %{
             endpoints: [endpoint],
             protocol: protocol
           }}
      }
    }
  end

  @doc """
  Returns the synchronous temporality defaults used by this profile.
  """
  def default_temporality_mapping, do: @default_temporality_mapping
end
