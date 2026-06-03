defmodule OtelBridge.Bridge do
  @moduledoc """
  Runtime process that records telemetry events as OpenTelemetry metrics.

  Most applications should use `OtelBridge` instead of starting this module
  directly.

  This module:

    1. receives prepared `Telemetry.Metrics` definitions
    2. creates matching OpenTelemetry instruments
    3. attaches telemetry handlers for each event name
    4. records incoming measurements into those instruments

  `Telemetry.Metrics.LastValue` is mapped to an observable gauge. Telemetry
  events update an internal ETS-backed latest-value store, and the
  OpenTelemetry reader observes the current values during collection.

  Last-value storage can be bounded with
  `reporter_options[:otel][:last_value]`:

    * `:ttl_ms` - stale series age in milliseconds, or `:infinity`
    * `:max_series` - maximum retained tag combinations per metric, or `:infinity`
    * `:on_overflow` - `:drop_new` or `:drop_oldest`
  """

  use GenServer
  require Logger

  @doc """
  Starts the bridge process for a set of metric definitions.
  """
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    case GenServer.start_link(__MODULE__, opts, name: name) do
      {:error, {:already_started, _pid}} -> :ignore
      other -> other
    end
  end

  @impl true
  def init(opts) do
    metrics = Keyword.get(opts, :metrics, [])
    meter = Keyword.get(opts, :meter) || meter()

    last_value_table =
      :ets.new(:otel_bridge_last_values, [
        :set,
        :public,
        read_concurrency: true,
        write_concurrency: true
      ])

    handlers =
      metrics
      |> Enum.group_by(& &1.event_name)
      |> Enum.map(fn {event_name, metrics} ->
        metrics_with_instruments =
          Enum.map(metrics, fn metric ->
            {metric, create_instrument(metric, meter, last_value_table)}
          end)

        handler_id = {__MODULE__, event_name, self()}

        :ok =
          :telemetry.attach(
            handler_id,
            event_name,
            &__MODULE__.handle_event/4,
            %{metrics: metrics_with_instruments}
          )

        handler_id
      end)

    Logger.info(
      "OtelBridge.Bridge initialized with #{length(metrics)} metrics on #{length(handlers)} telemetry events"
    )

    {:ok, %{handlers: handlers}}
  end

  @impl true
  def terminate(_reason, %{handlers: handlers}) do
    Enum.each(handlers, &:telemetry.detach/1)
  end

  @doc """
  Telemetry event handler that records measurements into OpenTelemetry
  instruments.

  For each configured metric, the handler:

    * checks whether the metric should be kept for the current metadata
    * extracts the measurement value
    * derives the exported tags
    * records the value into the created instrument
  """
  def handle_event(_event_name, measurements, metadata, %{metrics: metrics}) do
    ctx = OpenTelemetry.Ctx.get_current()

    Enum.each(metrics, fn {metric, instrument} ->
      with true <- keep?(metric, metadata),
           value when not is_nil(value) <- extract_measurement(metric, measurements, metadata) do
        record(ctx, metric, instrument, value, extract_tags(metric, metadata))
      end
    end)
  end

  def observe_last_value({table, name}) do
    observe_last_value({table, name, default_last_value_config()})
  end

  def observe_last_value({table, name, config}) do
    config = normalize_last_value_config(config)
    now = System.monotonic_time(:millisecond)

    prune_expired_last_values(table, name, config, now)

    table
    |> :ets.tab2list()
    |> Enum.flat_map(fn
      {{^name, tags}, {value, updated_at}} ->
        if expired_last_value?(updated_at, now, config), do: [], else: [{value, tags}]

      {{^name, tags}, value} ->
        [{value, tags}]

      _other ->
        []
    end)
  rescue
    ArgumentError -> []
  end

  def observe_last_value(table, name) do
    observe_last_value({table, name})
  end

  defp create_instrument(%Telemetry.Metrics.LastValue{} = metric, meter, last_value_table) do
    name = format_name(metric)
    config = last_value_config(metric)

    :otel_observable_gauge.create(
      meter,
      name,
      &__MODULE__.observe_last_value/1,
      {last_value_table, name, config},
      instrument_opts(metric)
    )

    {:last_value, last_value_table, name, config}
  end

  defp create_instrument(metric, meter, _last_value_table) do
    create_instrument(metric, meter)
  end

  defp create_instrument(%Telemetry.Metrics.Counter{} = metric, meter) do
    :otel_counter.create(meter, format_name(metric), instrument_opts(metric))
  end

  defp create_instrument(%Telemetry.Metrics.Sum{} = metric, meter) do
    :otel_counter.create(meter, format_name(metric), instrument_opts(metric))
  end

  defp create_instrument(%Telemetry.Metrics.Summary{} = metric, meter) do
    :otel_histogram.create(meter, format_name(metric), instrument_opts(metric))
  end

  defp create_instrument(%Telemetry.Metrics.Distribution{} = metric, meter) do
    :otel_histogram.create(meter, format_name(metric), instrument_opts(metric))
  end

  defp record(ctx, %Telemetry.Metrics.Counter{}, instrument, value, tags) do
    :otel_counter.add(ctx, instrument, value, tags)
  end

  defp record(ctx, %Telemetry.Metrics.Sum{}, instrument, value, tags) do
    :otel_counter.add(ctx, instrument, value, tags)
  end

  defp record(ctx, %Telemetry.Metrics.Summary{}, instrument, value, tags) do
    :otel_histogram.record(ctx, instrument, value, tags)
  end

  defp record(ctx, %Telemetry.Metrics.Distribution{}, instrument, value, tags) do
    :otel_histogram.record(ctx, instrument, value, tags)
  end

  defp record(_ctx, %Telemetry.Metrics.LastValue{}, {:last_value, table, name}, value, tags)
       when is_number(value) do
    record_last_value(table, name, default_last_value_config(), value, tags)
  end

  defp record(
         _ctx,
         %Telemetry.Metrics.LastValue{},
         {:last_value, table, name, config},
         value,
         tags
       )
       when is_number(value) do
    record_last_value(table, name, normalize_last_value_config(config), value, tags)
  end

  defp record_last_value(table, name, config, value, tags) do
    now = System.monotonic_time(:millisecond)
    key = {name, tags}

    prune_expired_last_values(table, name, config, now)

    cond do
      :ets.member(table, key) ->
        :ets.insert(table, {key, {value, now}})

      can_add_last_value_series?(table, name, config) ->
        :ets.insert(table, {key, {value, now}})

      config.on_overflow == :drop_oldest ->
        delete_oldest_last_value_series(table, name)
        :ets.insert(table, {key, {value, now}})

      true ->
        :ok
    end

    :ok
  rescue
    ArgumentError -> :ok
  end

  defp instrument_opts(metric) do
    %{
      unit: unit(metric.unit),
      description: metric.description || "#{format_name(metric)}"
    }
    |> Map.merge(Map.drop(otel_reporter_options(metric), [:last_value]))
  end

  defp last_value_config(metric) do
    metric
    |> otel_reporter_options()
    |> Map.get(:last_value, %{})
    |> normalize_last_value_config()
  end

  defp otel_reporter_options(metric) do
    case Keyword.get(metric.reporter_options, :otel, %{}) do
      opts when is_map(opts) -> opts
      opts when is_list(opts) -> Map.new(opts)
      _other -> %{}
    end
  end

  defp default_last_value_config do
    %{ttl_ms: :infinity, max_series: :infinity, on_overflow: :drop_new}
  end

  defp normalize_last_value_config(config) when is_list(config) do
    config |> Map.new() |> normalize_last_value_config()
  end

  defp normalize_last_value_config(config) when is_map(config) do
    Map.merge(default_last_value_config(), %{
      ttl_ms: normalize_limit(Map.get(config, :ttl_ms, :infinity)),
      max_series: normalize_limit(Map.get(config, :max_series, :infinity)),
      on_overflow: normalize_on_overflow(Map.get(config, :on_overflow, :drop_new))
    })
  end

  defp normalize_last_value_config(_config), do: default_last_value_config()

  defp normalize_limit(:infinity), do: :infinity
  defp normalize_limit(value) when is_integer(value) and value >= 0, do: value
  defp normalize_limit(_value), do: :infinity

  defp normalize_on_overflow(:drop_oldest), do: :drop_oldest
  defp normalize_on_overflow(_value), do: :drop_new

  defp prune_expired_last_values(_table, _name, %{ttl_ms: :infinity}, _now), do: :ok

  defp prune_expired_last_values(table, name, config, now) do
    table
    |> :ets.tab2list()
    |> Enum.each(fn
      {{^name, _tags} = key, {_value, updated_at}} ->
        if expired_last_value?(updated_at, now, config), do: :ets.delete(table, key)

      _other ->
        :ok
    end)
  rescue
    ArgumentError -> :ok
  end

  defp expired_last_value?(_updated_at, _now, %{ttl_ms: :infinity}), do: false

  defp expired_last_value?(updated_at, now, %{ttl_ms: ttl_ms}) do
    now - updated_at >= ttl_ms
  end

  defp can_add_last_value_series?(_table, _name, %{max_series: :infinity}), do: true

  defp can_add_last_value_series?(table, name, %{max_series: max_series}) do
    last_value_series_count(table, name) < max_series
  end

  defp last_value_series_count(table, name) do
    table
    |> :ets.tab2list()
    |> Enum.count(fn
      {{^name, _tags}, _value} -> true
      _other -> false
    end)
  rescue
    ArgumentError -> 0
  end

  defp delete_oldest_last_value_series(table, name) do
    table
    |> :ets.tab2list()
    |> Enum.flat_map(fn
      {{^name, _tags} = key, {_value, updated_at}} -> [{updated_at, key}]
      {{^name, _tags} = key, _value} -> [{0, key}]
      _other -> []
    end)
    |> Enum.min_by(fn {updated_at, _key} -> updated_at end, fn -> nil end)
    |> case do
      {_updated_at, key} -> :ets.delete(table, key)
      nil -> :ok
    end
  rescue
    ArgumentError -> :ok
  end

  defp unit(:unit), do: "1"
  defp unit(unit), do: "#{unit}"

  defp format_name(metric) do
    metric.name
    |> Enum.join(".")
    |> String.to_atom()
  end

  defp keep?(%{keep: nil}, _metadata), do: true
  defp keep?(%{keep: keep}, metadata), do: keep.(metadata)

  defp extract_measurement(%Telemetry.Metrics.Counter{}, _measurements, _metadata), do: 1

  defp extract_measurement(metric, measurements, metadata) do
    case metric.measurement do
      nil -> nil
      fun when is_function(fun, 1) -> fun.(measurements)
      fun when is_function(fun, 2) -> fun.(measurements, metadata)
      key -> measurements[key] || 1
    end
  end

  defp extract_tags(metric, metadata) do
    metric.tag_values.(metadata)
    |> Map.take(metric.tags)
  end

  defp meter do
    :opentelemetry_experimental.get_meter(:opentelemetry.get_application_scope(__MODULE__))
  end
end
