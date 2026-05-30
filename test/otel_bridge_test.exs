defmodule OtelBridgeTest do
  use ExUnit.Case

  import Telemetry.Metrics

  doctest OtelBridge

  defmodule DemoSpec do
    use OtelBridge.Spec

    @impl OtelBridge.Spec
    def metrics(meta) do
      [
        summary("demo.duration",
          event_name: [:otel_bridge, :demo],
          measurement: :duration,
          unit: {:native, :millisecond},
          tags: [:source],
          tag_values: fn metadata ->
            Map.put(metadata, :source, Keyword.fetch!(meta, :source))
          end
        )
      ]
    end
  end

  test "starts inets for OTLP HTTP metrics export" do
    {:ok, applications} = :application.get_key(:otel_bridge, :applications)

    assert :inets in applications
  end

  test "filters last_value metrics before bridging to otel" do
    metric = last_value("vm.memory.total", unit: :byte)

    assert [] = OtelBridge.prepare_metrics([metric])
  end

  test "loads metrics from spec modules with caller meta through the public api" do
    {:ok, pid} =
      OtelBridge.start_link(
        specs: [DemoSpec],
        meta: [source: "demo"],
        poller: [period: 5_000]
      )

    try do
      assert Enum.any?(:telemetry.list_handlers([:otel_bridge, :demo]), fn
               %{function: function} ->
                 function == (&OtelBridge.Bridge.handle_event/4)

               _handler ->
                 false
             end)

      :telemetry.execute([:otel_bridge, :demo], %{duration: 12_000_000}, %{})
    after
      GenServer.stop(pid)
    end
  end

  test "victoriametrics profile exports cumulative synchronous metrics" do
    assert %{
             module: :otel_metric_reader,
             config: %{
               default_temporality_mapping: %{
                 counter: :temporality_cumulative,
                 histogram: :temporality_cumulative,
                 updown_counter: :temporality_cumulative
               },
               exporter: {OtelBridge.Exporter, %{endpoints: ["http://localhost:4318"]}}
             }
           } =
             OtelBridge.metric_reader!(
               :victoria_metrics,
               export_interval_ms: 5_000,
               endpoint: "http://localhost:4318"
             )
  end
end
