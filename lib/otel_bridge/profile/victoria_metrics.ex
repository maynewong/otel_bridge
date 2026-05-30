defmodule OtelBridge.Profile.VictoriaMetrics do
  @moduledoc false

  @behaviour OtelBridge.Profile

  @default_temporality_mapping %{
    counter: :temporality_cumulative,
    histogram: :temporality_cumulative,
    updown_counter: :temporality_cumulative
  }

  @impl OtelBridge.Profile
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

  def default_temporality_mapping, do: @default_temporality_mapping
end
