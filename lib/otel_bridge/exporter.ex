defmodule OtelBridge.Exporter do
  @moduledoc """
  OTLP metrics exporter used by `OtelBridge` profiles.

  This module centralizes exporter initialization, transport handling, and
  shutdown logic for profile-defined metric readers.

  It is responsible for:

    * combining explicit exporter options with standard OTLP environment variables
    * initializing the underlying OTLP exporter state
    * exporting metric payloads over HTTP protobuf or gRPC
    * shutting down exporter-owned resources

  HTTP protobuf exports use the standard OTLP timeout of `10_000` milliseconds.
  `OTEL_EXPORTER_OTLP_METRICS_TIMEOUT` takes precedence over
  `OTEL_EXPORTER_OTLP_TIMEOUT`, and both take precedence over `:timeout_ms`.
  A value of `0` disables the timeout. Invalid or negative environment values
  are logged and ignored.

  The HTTP connection timeout defaults to `5_000` milliseconds and is capped by
  the total export timeout. It can be overridden with `:connect_timeout_ms`.
  These HTTP timeout options do not change gRPC transport behavior.
  """

  require Logger

  @default_metrics_path "/v1/metrics"
  @default_timeout_ms 10_000
  @default_connect_timeout_ms 5_000

  @doc """
  Initializes exporter state from explicit options plus standard OTLP
  environment variables.

  Supported HTTP timeout options are `:timeout_ms` and `:connect_timeout_ms`.
  Both accept a non-negative number of milliseconds or `:infinity`; `0` is
  normalized to `:infinity`.
  """
  def init(opts) do
    opts =
      opts
      |> put_timeout_defaults()
      |> merge_with_environment()

    case :otel_exporter_otlp.init(opts) do
      {:ok, state} ->
        {:ok, Map.merge(state, Map.take(opts, [:timeout_ms, :connect_timeout_ms]))}

      other ->
        other
    end
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

      export_http(
        address,
        Map.fetch!(state, :headers),
        body,
        Map.fetch!(state, :compression),
        Map.fetch!(List.first(Map.fetch!(state, :endpoints)), :ssl_options),
        Map.fetch!(state, :httpc_profile),
        state
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

  defp export_http(address, headers, body, compression, ssl_options, httpc_profile, state) do
    {headers, body} =
      case compression do
        :gzip -> {[{~c"content-encoding", ~c"gzip"} | headers], :zlib.gzip(body)}
        _compression -> {headers, body}
      end

    http_options = [
      {:ssl, ssl_options},
      {:timeout, Map.fetch!(state, :timeout_ms)},
      {:connect_timeout, Map.fetch!(state, :connect_timeout_ms)}
    ]

    case :httpc.request(
           :post,
           {address, headers, ~c"application/x-protobuf", body},
           http_options,
           [],
           httpc_profile
         ) do
      {:ok, {{_, code, _}, _, _}} when code >= 200 and code <= 202 ->
        :ok

      {:ok, {{_, code, _}, _, message}} ->
        Logger.info("error response from service exported to status=#{inspect(code)} #{message}")
        :error

      {:error, reason} ->
        Logger.info("client error exporting #{inspect(reason)}")
        :error
    end
  end

  defp put_timeout_defaults(opts) do
    timeout_ms =
      env_timeout("OTEL_EXPORTER_OTLP_METRICS_TIMEOUT") ||
        env_timeout("OTEL_EXPORTER_OTLP_TIMEOUT") ||
        normalize_timeout!(Map.get(opts, :timeout_ms, @default_timeout_ms), :timeout_ms)

    connect_timeout_ms =
      opts
      |> Map.get(:connect_timeout_ms, default_connect_timeout(timeout_ms))
      |> normalize_timeout!(:connect_timeout_ms)
      |> cap_timeout(timeout_ms)

    opts
    |> Map.put(:timeout_ms, timeout_ms)
    |> Map.put(:connect_timeout_ms, connect_timeout_ms)
  end

  defp env_timeout(name) do
    case System.get_env(name) do
      nil ->
        nil

      "" ->
        nil

      value ->
        case Integer.parse(value) do
          {timeout_ms, ""} when timeout_ms > 0 ->
            timeout_ms

          {0, ""} ->
            :infinity

          _invalid ->
            Logger.warning("invalid #{name}=#{inspect(value)}; ignoring")
            nil
        end
    end
  end

  defp normalize_timeout!(:infinity, _key), do: :infinity
  defp normalize_timeout!(0, _key), do: :infinity

  defp normalize_timeout!(timeout_ms, _key) when is_integer(timeout_ms) and timeout_ms > 0,
    do: timeout_ms

  defp normalize_timeout!(value, key) do
    raise ArgumentError,
          "expected #{inspect(key)} to be a non-negative integer or :infinity, got: #{inspect(value)}"
  end

  defp default_connect_timeout(:infinity), do: :infinity
  defp default_connect_timeout(_timeout_ms), do: @default_connect_timeout_ms

  defp cap_timeout(connect_timeout_ms, :infinity), do: connect_timeout_ms
  defp cap_timeout(:infinity, timeout_ms), do: timeout_ms
  defp cap_timeout(connect_timeout_ms, timeout_ms), do: min(connect_timeout_ms, timeout_ms)

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
