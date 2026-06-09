defmodule OtelBridge.MixProject do
  use Mix.Project

  @version "0.2.2"
  @description "Bridge Telemetry.Metrics definitions into OpenTelemetry metrics"
  @source_url "https://github.com/maynewong/otel_bridge"

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
      {:telemetry_metrics, "~> 0.6 or ~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:opentelemetry, "~> 1.7"},
      {:opentelemetry_exporter, "~> 1.10"},
      {:opentelemetry_api_experimental, "~> 0.5"},
      {:opentelemetry_experimental, "~> 0.5"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md", "LICENSE"],
      groups_for_modules: [
        "Public API": [OtelBridge, OtelBridge.Spec, OtelBridge.Profile],
        Profiles: [OtelBridge.Profile.VictoriaMetrics],
        Runtime: [
          OtelBridge.Application,
          OtelBridge.Supervisor,
          OtelBridge.Bridge,
          OtelBridge.Exporter
        ]
      ]
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      maintainers: ["maynewong"],
      links: %{"GitHub" => @source_url},
      files: ["lib", "mix.exs", "README.md", "CHANGELOG.md", "LICENSE", "examples"]
    ]
  end
end
