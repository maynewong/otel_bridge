# OtelBridge

`otel_bridge` bridges existing `Telemetry.Metrics` definitions to
OpenTelemetry metrics.

If your application already emits telemetry events and already describes
metrics with `Telemetry.Metrics`, this library provides a translation layer
that exports those metrics through the OpenTelemetry SDK.

It does not replace the OpenTelemetry SDK. It focuses on a single
responsibility:

- keep metric definitions in plain `Telemetry.Metrics`
- translate supported metric shapes into OpenTelemetry instruments
- provide small profile helpers for backend-specific reader configuration

## What problem does it solve?

Many Elixir applications already have useful `Telemetry.Metrics` modules, but
modern observability pipelines often expect OpenTelemetry export.

Without `otel_bridge`, teams typically have to choose between:

- rewriting metric definitions in a new abstraction
- duplicating metric definitions in two places
- mixing backend-specific exporter policy into business code

`otel_bridge` avoids that by separating the problem into three parts:

1. your app keeps defining metrics in `Telemetry.Metrics`
2. `OtelBridge` turns those definitions into OpenTelemetry instruments
3. `OtelBridge.Profile` modules hold backend-specific export policy

## How it works

Most integrations follow the same flow:

1. define one or more spec modules with `use OtelBridge.Spec`
2. start `OtelBridge` under your supervision tree
3. configure an OpenTelemetry metric reader, optionally via a profile helper

```text
MyApp.Metrics (OtelBridge.Spec)
           |
           v
       OtelBridge
     /           \
    v             v
Telemetry handlers  telemetry_poller
           \       /
            v     v
   OpenTelemetry metrics
            |
            v
   OtelBridge.Profile
            |
            v
      OTLP backend
```

## What the bridge maps

`otel_bridge` does not invent a second metrics DSL. It takes the
`Telemetry.Metrics` definitions you already have and maps them into
OpenTelemetry instruments at runtime.

The default bridge path maps:

- `Telemetry.Metrics.Counter` -> OpenTelemetry counter
- `Telemetry.Metrics.Sum` -> OpenTelemetry counter
- `Telemetry.Metrics.Summary` -> OpenTelemetry histogram
- `Telemetry.Metrics.Distribution` -> OpenTelemetry histogram

During that mapping, the bridge also:

- groups metrics by telemetry event name
- extracts measurements from event payloads
- applies `keep` filters when present
- derives exported tags from `tag_values`
- carries over unit, description, and explicit OTel reporter options

`Telemetry.Metrics.LastValue` is intentionally not mapped through the default
event-driven path. If you need that shape, use observer-style runtime logic or
custom observer children.

## Installation

Add `otel_bridge` to your dependencies:

```elixir
def deps do
  [
    {:otel_bridge, "~> 0.1.2"}
  ]
end
```

## Design goals

- keep business integration code small
- prefer Elixir behaviours over framework-specific DSLs
- keep backend policy out of business modules
- stay compatible with standard OpenTelemetry packages

## Supported metrics and scope

Supported today:

- `Telemetry.Metrics.Counter`
- `Telemetry.Metrics.Sum`
- `Telemetry.Metrics.Summary`
- `Telemetry.Metrics.Distribution`
- backend policy helpers through `OtelBridge.Profile`
- `:victoria_metrics` profile

Out of scope:

- tracing APIs
- logs
- automatic dashboard generation
- synchronous support for `Telemetry.Metrics.LastValue`

## Step 1: define metrics

Start by writing a spec module with `OtelBridge.Spec` that returns ordinary
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

The `meta` argument comes from the `:meta` option you pass to `OtelBridge`.
Use it for shared values such as service name, default tags, or deployment
metadata.

## Step 2: start the bridge

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

At startup, `OtelBridge`:

1. loads metrics from `:metrics`, `:specs`, and `:optional_specs`
2. filters out metric shapes the default runtime does not support
3. starts a telemetry bridge process for event-driven metrics
4. starts `:telemetry_poller` for periodic measurements

Accepted options:

- `:metrics` - raw `Telemetry.Metrics` definitions
- `:specs` - spec modules implementing `OtelBridge.Spec`
- `:optional_specs` - spec modules that may or may not be available
- `:measurements` - `:telemetry_poller` measurements
- `:meta` - keyword metadata passed to spec modules
- `:poller` - `:telemetry_poller` options
- `:observer_children` - custom observer children for gauge-like metrics

## Step 3: configure metric export

`otel_bridge` does not own the full OpenTelemetry SDK configuration. It helps
build metric reader configuration for a chosen backend profile.

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

You can also configure the OpenTelemetry SDK directly and use `otel_bridge`
only for metrics bridging.

## Complete examples

See the runnable examples in:

- [`examples/basic_usage.exs`](./examples/basic_usage.exs)
- [`examples/runtime_config.exs`](./examples/runtime_config.exs)

The first shows the smallest business integration shape.
The second shows how to wire the VictoriaMetrics profile into
`config/runtime.exs`.

## Where to look next

Once the basic flow makes sense, these modules are the most useful references:

- `OtelBridge` - the main integration entrypoint
- `OtelBridge.Spec` - how to define metrics
- `OtelBridge.Profile` - how export profiles work
- `OtelBridge.Profile.VictoriaMetrics` - the built-in backend profile

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


