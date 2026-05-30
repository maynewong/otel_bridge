defmodule OtelBridge.Exporter do
  @moduledoc """
  OTLP metrics exporter used by `OtelBridge` profiles.

  This module focuses on metrics export wiring and environment merging. Most
  callers should access it indirectly via `OtelBridge.Profile` helpers.
  """

  require Logger

  @default_metrics_path "/v1/metrics"

  @doc """
  Initializes exporter state from explicit options plus standard OTLP
  environment variables.
  """
  def init(opts) do
    opts
    |> merge_with_environment()
    |> :otel_exporter_otlp.init()
  end

  @doc """
  Exports metric payloads through the configured OTLP transport.
  """
  def export(:metrics, metrics, resource, state), do: export(metrics, resource, state)
  def export(_kind, _data, _resource, _state), do: :ok

  def export([], _resource, _state), do: :ok

  def export(metrics, resource, %{protocol: :http_protobuf} = state) do
    with {:ok, address} <- http_address(state) do
      body =
        metrics
        |> :otel_otlp_metrics.to_proto(resource)
        |> :opentelemetry_exporter_metrics_service_pb.encode_msg(:export_metrics_service_request)

      :otel_exporter_otlp.export_http(
        address,
        Map.fetch!(state, :headers),
        body,
        Map.fetch!(state, :compression),
        Map.fetch!(List.first(Map.fetch!(state, :endpoints)), :ssl_options),
        Map.fetch!(state, :httpc_profile)
      )
    end
  end

  def export(metrics, resource, %{protocol: :grpc} = state) do
    request = :otel_otlp_metrics.to_proto(metrics, resource)

    :otel_exporter_otlp.export_grpc(
      :ctx.new(),
      :opentelemetry_metrics_service,
      Map.fetch!(state, :grpc_metadata),
      request,
      Map.fetch!(state, :channel)
    )
  end

  def export(_metrics, _resource, _state), do: {:error, :unsupported_protocol}

  @doc """
  Shuts down any exporter-owned network resources.
  """
  def shutdown(%{channel_pid: nil}), do: :ok

  def shutdown(%{channel_pid: pid}) when is_pid(pid) do
    :grpcbox_channel.stop(pid)
    :ok
  end

  def shutdown(_state), do: :ok

  defp http_address(%{endpoints: [endpoint | _]}) do
    address =
      :uri_string.normalize(%{
        scheme: Map.fetch!(endpoint, :scheme),
        host: Map.fetch!(endpoint, :host),
        port: Map.fetch!(endpoint, :port),
        path: Map.fetch!(endpoint, :path)
      })

    case address do
      {:error, type, error} ->
        Logger.info(
          "error normalizing OTLP metrics export URI: #{inspect(type)} #{inspect(error)}"
        )

        {:error, {type, error}}

      address ->
        {:ok, address}
    end
  end

  defp merge_with_environment(opts) do
    Application.load(:opentelemetry_exporter)
    app_env = Application.get_all_env(:opentelemetry_exporter)

    :otel_exporter_otlp.merge_with_environment(
      config_mapping(),
      app_env,
      opts,
      :otlp_metrics_endpoint,
      :otlp_metrics_headers,
      :otlp_metrics_protocol,
      :otlp_metrics_compression,
      @default_metrics_path
    )
  end

  defp config_mapping do
    [
      {~c"OTEL_EXPORTER_OTLP_ENDPOINT", :otlp_endpoint, :url},
      {~c"OTEL_EXPORTER_OTLP_METRICS_ENDPOINT", :otlp_metrics_endpoint, :url},
      {~c"OTEL_EXPORTER_OTLP_HEADERS", :otlp_headers, :key_value_list},
      {~c"OTEL_EXPORTER_OTLP_METRICS_HEADERS", :otlp_metrics_headers, :key_value_list},
      {~c"OTEL_EXPORTER_OTLP_PROTOCOL", :otlp_protocol, :otlp_protocol},
      {~c"OTEL_EXPORTER_OTLP_METRICS_PROTOCOL", :otlp_metrics_protocol, :otlp_protocol},
      {~c"OTEL_EXPORTER_OTLP_COMPRESSION", :otlp_compression, :existing_atom},
      {~c"OTEL_EXPORTER_OTLP_METRICS_COMPRESSION", :otlp_metrics_compression, :existing_atom},
      {~c"OTEL_EXPORTER_SSL_OPTIONS", :ssl_options, :key_value_list}
    ]
  end
end
