defmodule OtelBridgeTest do
  use ExUnit.Case

  import ExUnit.CaptureLog
  import Telemetry.Metrics
  require Record

  doctest OtelBridge

  @timeout_env_vars ["OTEL_EXPORTER_OTLP_TIMEOUT", "OTEL_EXPORTER_OTLP_METRICS_TIMEOUT"]

  Record.defrecordp(
    :datapoint,
    Record.extract(:datapoint, from_lib: "opentelemetry_experimental/include/otel_metrics.hrl")
  )

  Record.defrecordp(
    :metric,
    Record.extract(:metric, from_lib: "opentelemetry_experimental/include/otel_metrics.hrl")
  )

  Record.defrecordp(
    :instrumentation_scope,
    Record.extract(:instrumentation_scope,
      from_lib: "opentelemetry_api/include/opentelemetry.hrl"
    )
  )

  Record.defrecordp(
    :metric_sum,
    :sum,
    Record.extract(:sum, from_lib: "opentelemetry_experimental/include/otel_metrics.hrl")
  )

  setup do
    previous_env = Map.new(@timeout_env_vars, &{&1, System.get_env(&1)})
    Enum.each(@timeout_env_vars, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(previous_env, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)

    :ok
  end

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

    assert [{30, %{queue: "default"}}] = OtelBridge.Bridge.observe_last_value(table, :queue_depth)

    :ets.delete(table)
  end

  test "last_value metrics ignore stale ETS table references" do
    table = :ets.new(:otel_bridge_last_value_stale_table_test, [:set, :public])

    metric =
      last_value("vm.memory.total",
        event_name: [:otel_bridge, :stale_last_value],
        measurement: :total
      )

    instrument = {:last_value, table, :vm_memory_total}

    :ets.delete(table)

    assert :ok =
             OtelBridge.Bridge.handle_event(
               [:otel_bridge, :stale_last_value],
               %{total: 100},
               %{},
               %{metrics: [{metric, instrument}]}
             )
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

  test "victoriametrics profile leaves OTLP timeout defaults to the exporter" do
    assert %{
             config: %{
               exporter: {OtelBridge.Exporter, exporter_opts}
             }
           } =
             OtelBridge.metric_reader!(
               :victoria_metrics,
               export_interval_ms: 5_000,
               endpoint: "http://localhost:4318"
             )

    refute Map.has_key?(exporter_opts, :timeout_ms)
    refute Map.has_key?(exporter_opts, :connect_timeout_ms)
  end

  test "exporter uses the OTLP default timeout" do
    assert {:ok,
            %{
              timeout_ms: 10_000,
              connect_timeout_ms: 5_000
            }} =
             OtelBridge.Exporter.init(%{
               endpoints: ["http://localhost:4318"],
               protocol: :http_protobuf
             })
  end

  test "exporter caps the default connection timeout at the configured OTLP timeout" do
    assert {:ok,
            %{
              timeout_ms: 1_000,
              connect_timeout_ms: 1_000
            }} =
             OtelBridge.Exporter.init(%{
               endpoints: ["http://localhost:4318"],
               protocol: :http_protobuf,
               timeout_ms: 1_000
             })
  end

  test "exporter treats a zero OTLP timeout as no limit" do
    with_env("OTEL_EXPORTER_OTLP_METRICS_TIMEOUT", "0", fn ->
      assert {:ok, %{timeout_ms: :infinity, connect_timeout_ms: :infinity}} =
               OtelBridge.Exporter.init(%{
                 endpoints: ["http://localhost:4318"],
                 protocol: :http_protobuf
               })
    end)
  end

  test "exporter ignores an invalid OTLP timeout environment variable" do
    log =
      capture_log(fn ->
        with_env("OTEL_EXPORTER_OTLP_METRICS_TIMEOUT", "invalid", fn ->
          assert {:ok, %{timeout_ms: 10_000, connect_timeout_ms: 5_000}} =
                   OtelBridge.Exporter.init(%{
                     endpoints: ["http://localhost:4318"],
                     protocol: :http_protobuf
                   })
        end)
      end)

    assert log =~ "OTEL_EXPORTER_OTLP_METRICS_TIMEOUT"
    assert log =~ "ignoring"
  end

  test "exporter ignores a negative OTLP timeout environment variable" do
    log =
      capture_log(fn ->
        with_env("OTEL_EXPORTER_OTLP_METRICS_TIMEOUT", "-1", fn ->
          assert {:ok, %{timeout_ms: 10_000, connect_timeout_ms: 5_000}} =
                   OtelBridge.Exporter.init(%{
                     endpoints: ["http://localhost:4318"],
                     protocol: :http_protobuf
                   })
        end)
      end)

    assert log =~ "OTEL_EXPORTER_OTLP_METRICS_TIMEOUT"
    assert log =~ "ignoring"
  end

  test "metrics-specific OTLP timeout takes precedence over the generic timeout" do
    with_env("OTEL_EXPORTER_OTLP_TIMEOUT", "8000", fn ->
      with_env("OTEL_EXPORTER_OTLP_METRICS_TIMEOUT", "2000", fn ->
        assert {:ok, %{timeout_ms: 2_000, connect_timeout_ms: 2_000}} =
                 OtelBridge.Exporter.init(%{
                   endpoints: ["http://localhost:4318"],
                   protocol: :http_protobuf
                 })
      end)
    end)
  end

  test "HTTP protobuf metrics export sends a valid content type" do
    assert {:ok, request} = export_to_local_collector()

    assert request =~ "content-type: application/x-protobuf\r\n"
  end

  test "gzip HTTP protobuf metrics export sends a valid content encoding" do
    assert {:ok, request} = export_to_local_collector(compression: :gzip)

    assert request =~ "content-type: application/x-protobuf\r\n"
    assert request =~ "content-encoding: gzip\r\n"
  end

  defp with_env(name, value, fun) do
    previous = System.get_env(name)
    System.put_env(name, value)

    try do
      fun.()
    after
      if previous, do: System.put_env(name, previous), else: System.delete_env(name)
    end
  end

  defp export_to_local_collector(opts \\ []) do
    {:ok, listen_socket} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, packet: :raw])

    {:ok, port} = :inet.port(listen_socket)
    parent = self()

    server =
      spawn_link(fn ->
        {:ok, socket} = :gen_tcp.accept(listen_socket)
        {:ok, request} = recv_http_request(socket, <<>>)
        :ok = :gen_tcp.send(socket, "HTTP/1.1 200 OK\r\ncontent-length: 0\r\n\r\n")
        send(parent, {:collector_request, request})
        :gen_tcp.close(socket)
        :gen_tcp.close(listen_socket)
      end)

    exporter_opts =
      %{
        endpoints: ["http://127.0.0.1:#{port}"],
        protocol: :http_protobuf
      }
      |> Map.merge(Map.new(opts))

    with {:ok, state} <- OtelBridge.Exporter.init(exporter_opts),
         :ok <- OtelBridge.Exporter.export(sample_metrics(), sample_resource(), state) do
      receive do
        {:collector_request, request} -> {:ok, request}
      after
        1_000 ->
          Process.exit(server, :kill)
          {:error, :collector_timeout}
      end
    end
  end

  defp recv_http_request(socket, buffer) do
    with {:ok, headers_end} <- find_headers_end(buffer),
         {:ok, content_length} <- content_length(buffer, headers_end) do
      request_length = headers_end + content_length

      if byte_size(buffer) >= request_length do
        {:ok, binary_part(buffer, 0, request_length)}
      else
        recv_more(socket, buffer)
      end
    else
      :more -> recv_more(socket, buffer)
    end
  end

  defp recv_more(socket, buffer) do
    case :gen_tcp.recv(socket, 0, 1_000) do
      {:ok, data} -> recv_http_request(socket, buffer <> data)
      error -> error
    end
  end

  defp find_headers_end(buffer) do
    case :binary.match(buffer, "\r\n\r\n") do
      {index, 4} -> {:ok, index + 4}
      :nomatch -> :more
    end
  end

  defp content_length(buffer, headers_end) do
    headers =
      buffer
      |> binary_part(0, headers_end)
      |> String.downcase()

    case Regex.run(~r/content-length:\s*(\d+)/, headers) do
      [_, content_length] -> {:ok, String.to_integer(content_length)}
      nil -> {:ok, 0}
    end
  end

  defp sample_metrics do
    now = :opentelemetry.timestamp()

    [
      metric(
        name: "test.counter",
        scope:
          instrumentation_scope(
            name: "otel_bridge_test",
            version: "",
            schema_url: :undefined
          ),
        description: "",
        unit: "1",
        data:
          metric_sum(
            aggregation_temporality: :temporality_cumulative,
            is_monotonic: true,
            datapoints: [
              datapoint(
                attributes: %{},
                start_time: now,
                time: now,
                value: 1,
                exemplars: [],
                flags: 0
              )
            ]
          )
      )
    ]
  end

  defp sample_resource do
    :otel_resource.create([])
  end
end
