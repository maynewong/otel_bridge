defmodule OtelBridge.MixProject do
  use Mix.Project

  @version "0.1.0"
  @description "Bridge Telemetry.Metrics definitions into OpenTelemetry metrics"

  def project do
    [
      app: :otel_bridge,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      description: @description,
      package: package(),
      docs: docs(),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets]
    ]
  end

  defp deps do
    [
      {:telemetry, "~> 1.0"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:opentelemetry, "~> 1.7"},
      {:opentelemetry_exporter, "~> 1.10"},
      {:opentelemetry_api_experimental, "~> 0.5"},
      {:opentelemetry_experimental, "~> 0.5"}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"]
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      files: ["lib", "mix.exs", "README.md", "CHANGELOG.md", "LICENSE", "examples"]
    ]
  end
end
