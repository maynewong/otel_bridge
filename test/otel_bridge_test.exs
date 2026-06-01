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

  test "keeps last_value metrics for observable gauges" do
    metric = last_value("vm.memory.total", unit: :byte)

    assert [%Telemetry.Metrics.LastValue{}] = OtelBridge.prepare_metrics([metric])
  end

  test "last_value metrics observe the latest value for each tag set" do
    table = :ets.new(:otel_bridge_last_value_test, [:set, :public])

    metric =
      last_value("vm.memory.total",
        event_name: [:otel_bridge, :last_value],
        measurement: :total,
        tags: [:node]
      )

    instrument = {:last_value, table, :vm_memory_total}

    OtelBridge.Bridge.handle_event(
      [:otel_bridge, :last_value],
      %{total: 100},
      %{node: "node-a"},
      %{metrics: [{metric, instrument}]}
    )

    OtelBridge.Bridge.handle_event(
      [:otel_bridge, :last_value],
      %{total: 200},
      %{node: "node-a"},
      %{metrics: [{metric, instrument}]}
    )

    OtelBridge.Bridge.handle_event(
      [:otel_bridge, :last_value],
      %{total: 300},
      %{node: "node-b"},
      %{metrics: [{metric, instrument}]}
    )

    assert [{200, %{node: "node-a"}}, {300, %{node: "node-b"}}] =
             table
             |> OtelBridge.Bridge.observe_last_value(:vm_memory_total)
             |> Enum.sort()

    :ets.delete(table)
  end

  test "last_value metrics drop expired tag sets while observing" do
    table = :ets.new(:otel_bridge_last_value_ttl_test, [:set, :public])
    now = System.monotonic_time(:millisecond)

    :ets.insert(table, {{:queue_depth, %{queue: "old"}}, {10, now - 1_000}})
    :ets.insert(table, {{:queue_depth, %{queue: "fresh"}}, {20, now}})

    assert [{20, %{queue: "fresh"}}] =
             OtelBridge.Bridge.observe_last_value(
               {table, :queue_depth, %{ttl_ms: 100, max_series: :infinity}}
             )

    assert [] = :ets.lookup(table, {:queue_depth, %{queue: "old"}})

    :ets.delete(table)
  end

  test "last_value metrics drop new tag sets after max_series is reached" do
    table = :ets.new(:otel_bridge_last_value_max_series_test, [:set, :public])

    metric =
      last_value("queue.depth",
        event_name: [:otel_bridge, :queue],
        measurement: :depth,
        tags: [:queue]
      )

    instrument =
      {:last_value, table, :queue_depth,
       %{ttl_ms: :infinity, max_series: 1, on_overflow: :drop_new}}

    OtelBridge.Bridge.handle_event(
      [:otel_bridge, :queue],
      %{depth: 10},
      %{queue: "default"},
      %{metrics: [{metric, instrument}]}
    )

    OtelBridge.Bridge.handle_event(
      [:otel_bridge, :queue],
      %{depth: 20},
      %{queue: "critical"},
      %{metrics: [{metric, instrument}]}
    )

    OtelBridge.Bridge.handle_event(
      [:otel_bridge, :queue],
      %{depth: 30},
      %{queue: "default"},
      %{metrics: [{metric, instrument}]}
    )

    assert [{30, %{queue: "default"}}] =
             OtelBridge.Bridge.observe_last_value(table, :queue_depth)

    :ets.delete(table)
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
