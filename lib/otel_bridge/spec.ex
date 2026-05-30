defmodule OtelBridge.Spec do
  @moduledoc false

  @callback metrics(keyword()) :: [Telemetry.Metrics.t()]

  defmacro __using__(_opts) do
    quote do
      import Telemetry.Metrics

      @behaviour OtelBridge.Spec
    end
  end
end
