# OtelBridge

`otel_bridge` is a small adapter layer for teams that already describe metrics
with `Telemetry.Metrics`, but want to export them through OpenTelemetry.

It does not try to replace `opentelemetry`, `opentelemetry_api`, or
`opentelemetry_exporter`. Instead, it sits on top of them and provides:

- a small public API
- a behaviour for metric spec modules
- a bridge from `Telemetry.Metrics` to OpenTelemetry instruments
- backend-specific profile helpers such as VictoriaMetrics

## Installation

Add `otel_bridge` to your dependencies:

```elixir
def deps do
  [
    {:otel_bridge, "~> 0.1.0"}
  ]
end
```

## Design goals

- keep business integration code small
- prefer Elixir behaviours over framework-specific DSLs
- keep backend policy out of business modules
- stay compatible with standard OpenTelemetry packages

## Supported scope

`otel_bridge` currently focuses on one job:

- bridge `Telemetry.Metrics` definitions into OpenTelemetry metrics

What it supports today:

- `Telemetry.Metrics.Counter`
- `Telemetry.Metrics.Sum`
- `Telemetry.Metrics.Summary`
- `Telemetry.Metrics.Distribution`
- backend policy helpers through `OtelBridge.Profile`
- `:victoria_metrics` profile

What it does not support today:

- tracing APIs
- logs
- automatic dashboard generation
- synchronous support for `Telemetry.Metrics.LastValue`

## Define metrics

Create a module that uses `OtelBridge.Spec` and returns ordinary
`Telemetry.Metrics` definitions:

```elixir
defmodule MyApp.Metrics do
  use OtelBridge.Spec

  @impl OtelBridge.Spec
  def metrics(meta) do
    [
      summary("http.server.duration",
        event_name: [:my_app, :http, :stop],
        measurement: :duration,
        unit: {:native, :millisecond},
        tags: [:route, :status_code],
        tag_values: fn metadata ->
          metadata
          |> Map.put(:route, metadata[:route] || "unknown")
          |> Map.put(:status_code, metadata[:status_code] || 500)
          |> Map.put(:service, Keyword.get(meta, :service))
        end
      )
    ]
  end
end
```

## Start the bridge

Use `OtelBridge` directly in your supervision tree:

```elixir
children = [
  {OtelBridge,
   specs: [MyApp.Metrics],
   optional_specs: [MyApp.OptionalMetrics],
   measurements: [{MyApp.Measurements, :dispatch, []}],
   meta: [service: "my_app"],
   poller: [period: 5_000]}
]
```

Accepted options:

- `:metrics` - raw `Telemetry.Metrics` definitions
- `:specs` - spec modules implementing `OtelBridge.Spec`
- `:optional_specs` - spec modules that may or may not be available
- `:measurements` - `:telemetry_poller` measurements
- `:meta` - keyword metadata passed to spec modules
- `:poller` - `:telemetry_poller` options
- `:observer_children` - custom observer children for gauge-like metrics

## Configure metric export

`otel_bridge` does not own the whole OpenTelemetry SDK configuration. It only
helps you build metric reader config for a chosen backend profile.

For VictoriaMetrics:

```elixir
config :opentelemetry_experimental,
  readers: [
    OtelBridge.metric_reader!(:victoria_metrics,
      export_interval_ms: 5_000,
      endpoint: "http://localhost:4318"
    )
  ]
```

The VictoriaMetrics profile exports synchronous metrics with cumulative
temporality for:

- `counter`
- `histogram`
- `updown_counter`

## Complete examples

See the runnable examples in:

- [`examples/basic_usage.exs`](./examples/basic_usage.exs)
- [`examples/runtime_config.exs`](./examples/runtime_config.exs)

The first shows the smallest business integration shape.
The second shows how to wire the VictoriaMetrics profile into
`config/runtime.exs`.

## Contract guarantees

`otel_bridge` aims to keep these behaviors stable within a compatible minor
release line:

- `use OtelBridge.Spec` remains the standard way to define spec modules
- `{OtelBridge, ...}` remains the standard supervision entrypoint
- `OtelBridge.metric_reader!/2` remains the profile-based metric reader helper
- `Telemetry.Metrics.LastValue` continues to be filtered out by the bridge
- the `:victoria_metrics` profile keeps cumulative temporality for synchronous
  counters, histograms, and updown counters

These guarantees are backed by tests in `test/`.

## Versioning policy

`otel_bridge` follows semantic versioning.

- patch releases fix bugs and documentation without changing supported public
  API
- minor releases may add new profiles, new helpers, and new supported metric
  shapes in a backwards-compatible way
- major releases may change public APIs, profile names, or contract guarantees

Behavior that is not documented in this README or module docs should be treated
as internal and may change between minor releases.

See [`CHANGELOG.md`](./CHANGELOG.md) for release history.

## Scope

`otel_bridge` is intentionally focused on metrics bridging and export policy.

It does not:

- replace `OpenTelemetry.Tracer`
- replace the OpenTelemetry SDK
- provide business-specific metric definitions

Use the standard OpenTelemetry packages for tracing APIs and SDK setup, and use
`otel_bridge` where you need a clean `Telemetry.Metrics` to OTel migration path.

