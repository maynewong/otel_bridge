defmodule OtelBridge.Application do
  @moduledoc """
  OTP application module for `otel_bridge`.

  It exists so the library and its runtime dependencies are started correctly
  when used as an application dependency. Applications should use `OtelBridge`
  as the public integration entrypoint.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = []

    opts = [strategy: :one_for_one, name: OtelBridge.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
