# OtelBridge

`otel_bridge` bridges existing `Telemetry.Metrics` definitions to
OpenTelemetry metrics.

It is intended for applications that already emit telemetry events and already
define metrics with `Telemetry.Metrics`, but want to export those metrics
through the OpenTelemetry SDK.

It does not replace the OpenTelemetry SDK. Its role is narrow:

- keep metric definitions in plain `Telemetry.Metrics`
- translate supported metric shapes into OpenTelemetry instruments
- provide small profile helpers for backend-specific reader configuration

## When to use it

Use `otel_bridge` when:

- your app already uses `Telemetry.Metrics`
- you want to adopt OpenTelemetry metrics without rewriting existing metric
  definitions
- you want backend-specific export configuration to stay outside business code

## How it works

Most integrations follow this flow:

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

## Installation

Add `otel_bridge` to your dependencies:

```elixir
def deps do
  [
    {:otel_bridge, "~> 0.1.2"}
  ]
end
```

## Quick start

### 1. Define metrics

Create a spec module with `OtelBridge.Spec`:

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

The `meta` argument comes from the `:meta` option passed to `OtelBridge`. Use
it for shared values such as service name, default tags, or environment data.

### 2. Start the bridge

Add `OtelBridge` to your supervision tree:

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

Common options:

- `:metrics` - raw `Telemetry.Metrics` definitions
- `:specs` - modules implementing `OtelBridge.Spec`
- `:optional_specs` - spec modules to load when available
- `:measurements` - `:telemetry_poller` measurements
- `:meta` - shared keyword metadata passed to spec modules
- `:poller` - `:telemetry_poller` options
- `:observer_children` - custom children for observable or gauge-like metrics

### 3. Configure metric export

`otel_bridge` helps build metric reader configuration, but the OpenTelemetry
SDK remains configured through the standard OpenTelemetry packages.

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

You can also configure the reader yourself and use `otel_bridge` only for
metrics bridging.

## Metric mapping

The default bridge path maps:

- `Telemetry.Metrics.Counter` -> OpenTelemetry counter
- `Telemetry.Metrics.Sum` -> OpenTelemetry counter
- `Telemetry.Metrics.Summary` -> OpenTelemetry histogram
- `Telemetry.Metrics.Distribution` -> OpenTelemetry histogram
- `Telemetry.Metrics.LastValue` -> OpenTelemetry observable gauge

During that process, the bridge also:

- groups metrics by telemetry event name
- extracts measurements from event payloads
- applies `keep` filters when present
- derives exported tags from `tag_values`
- carries over unit, description, and explicit OTel reporter options

`Telemetry.Metrics.LastValue` is handled differently from synchronous metrics.
Telemetry events update an internal latest-value store, and the OpenTelemetry
reader observes that store through an observable gauge callback during
collection. This preserves the current-state semantics of gauges without
treating absolute values as counter deltas.

### `last_value` cardinality protection

Each `last_value` series is keyed by `{metric_name, tags}`. Low-cardinality
gauges such as VM memory, queue depth, or cache size are a natural fit. Avoid
high-cardinality tags such as request IDs, user IDs, or raw dynamic URLs unless
you configure bounds.

Use `reporter_options[:otel][:last_value]` to cap retained series:

```elixir
last_value("queue.depth",
  event_name: [:my_app, :queue, :stats],
  measurement: :depth,
  tags: [:queue],
  reporter_options: [
    otel: [
      last_value: [
        ttl_ms: 300_000,
        max_series: 1_000,
        on_overflow: :drop_new
      ]
    ]
  ]
)
```

Supported options:

- `:ttl_ms` - deletes stale series after the given age in milliseconds;
  defaults to `:infinity`
- `:max_series` - maximum retained tag combinations per metric; defaults to
  `:infinity`
- `:on_overflow` - `:drop_new` to ignore new tag combinations, or
  `:drop_oldest` to evict the oldest retained series; defaults to `:drop_new`

Expired series are pruned when new `last_value` events arrive and when the OTel
reader observes the metric.

## Scope

Supported today:

- `Telemetry.Metrics.Counter`
- `Telemetry.Metrics.Sum`
- `Telemetry.Metrics.Summary`
- `Telemetry.Metrics.Distribution`
- `Telemetry.Metrics.LastValue`
- backend policy helpers through `OtelBridge.Profile`
- `:victoria_metrics` profile

Out of scope:

- tracing APIs
- logs
- automatic dashboard generation

## Examples and references

See the runnable examples in:

- [`examples/basic_usage.exs`](./examples/basic_usage.exs)
- [`examples/runtime_config.exs`](./examples/runtime_config.exs)

The first shows the smallest business integration shape.
The second shows how to wire the VictoriaMetrics profile into
`config/runtime.exs`.

Useful modules:

- `OtelBridge` - the main integration entrypoint
- `OtelBridge.Spec` - how to define metrics
- `OtelBridge.Profile` - how export profiles work
- `OtelBridge.Profile.VictoriaMetrics` - the built-in backend profile

See [`CHANGELOG.md`](./CHANGELOG.md) for release history.


