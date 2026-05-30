defmodule OtelBridge.ContractTest do
  use ExUnit.Case

  import Telemetry.Metrics

  defmodule RequiredSpec do
    use OtelBridge.Spec

    @impl OtelBridge.Spec
    def metrics(meta) do
      [
        counter("contract.requests",
          event_name: [:otel_bridge, :contract],
          tags: [:service],
          tag_values: fn metadata ->
            Map.put(metadata, :service, Keyword.fetch!(meta, :service))
          end
        )
      ]
    end
  end

  test "child_spec keeps the public entrypoint stable" do
    assert %{id: OtelBridge, start: {OtelBridge, :start_link, [[specs: []]]}} =
             OtelBridge.child_spec(specs: [])
  end

  test "optional specs are ignored when the module is unavailable" do
    {:ok, pid} =
      OtelBridge.start_link(
        specs: [RequiredSpec],
        optional_specs: [Missing.Optional.Spec],
        meta: [service: "contract"],
        poller: [period: 5_000]
      )

    try do
      assert Enum.any?(:telemetry.list_handlers([:otel_bridge, :contract]), fn
               %{function: function} ->
                 function == (&OtelBridge.Bridge.handle_event/4)

               _handler ->
                 false
             end)
    after
      GenServer.stop(pid)
    end
  end

  test "named profiles resolve through the public helper" do
    assert OtelBridge.Profile.VictoriaMetrics ==
             OtelBridge.Profile.resolve!(:victoria_metrics)
  end

  test "named profiles produce an otel metric reader through the public api" do
    assert %{
             module: :otel_metric_reader,
             config: %{export_interval_ms: 1_000}
           } =
             OtelBridge.metric_reader!(
               :victoria_metrics,
               export_interval_ms: 1_000,
               endpoint: "http://localhost:4318"
             )
  end

  test "last_value metrics stay outside the bridge contract" do
    metrics = [
      last_value("contract.last_value", event_name: [:otel_bridge, :contract, :last_value]),
      counter("contract.count", event_name: [:otel_bridge, :contract, :last_value])
    ]

    assert [%Telemetry.Metrics.Counter{}] = OtelBridge.prepare_metrics(metrics)
  end
end
