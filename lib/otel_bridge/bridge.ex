defmodule OtelBridge.Bridge do
  @moduledoc false

  use GenServer
  require Logger

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

    handlers =
      metrics
      |> Enum.group_by(& &1.event_name)
      |> Enum.map(fn {event_name, metrics} ->
        metrics_with_instruments =
          Enum.map(metrics, fn metric ->
            {metric, create_instrument(metric, meter)}
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

  def handle_event(_event_name, measurements, metadata, %{metrics: metrics}) do
    ctx = OpenTelemetry.Ctx.get_current()

    Enum.each(metrics, fn {metric, instrument} ->
      with true <- keep?(metric, metadata),
           value when not is_nil(value) <- extract_measurement(metric, measurements, metadata) do
        record(ctx, metric, instrument, value, extract_tags(metric, metadata))
      end
    end)
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

  defp instrument_opts(metric) do
    %{
      unit: unit(metric.unit),
      description: metric.description || "#{format_name(metric)}"
    }
    |> Map.merge(Keyword.get(metric.reporter_options, :otel, %{}))
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
