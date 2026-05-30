defmodule OtelBridge.Application do
  @moduledoc """
  OTP application definition for `otel_bridge`.

  The library itself does not need a long-running supervision tree at
  application boot, but it declares its runtime application requirements here
  so consumers get a working environment out of the box.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = []

    opts = [strategy: :one_for_one, name: OtelBridge.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
