# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog and the project follows Semantic
Versioning.

## [0.2.3] - 2026-06-10

### Fixed

- fixed HTTP protobuf metrics export request types so `:httpc` accepts the
  OTLP `Content-Type` and gzip `Content-Encoding` fields

## [0.2.2] - 2026-06-09

### Added

- added finite HTTP request and connection timeouts for OTLP metrics export
- added support for `OTEL_EXPORTER_OTLP_TIMEOUT` and
  `OTEL_EXPORTER_OTLP_METRICS_TIMEOUT`

### Fixed

- aligned the default OTLP export timeout with the standard `10_000`
  millisecond value
- treated a timeout value of `0` as no limit and ignored invalid environment
  values with a warning instead of failing exporter initialization
- capped the HTTP connection timeout at the total export timeout

## [0.2.1] - 2026-06-02

### Fixed

- ignored stale ETS table references while recording `last_value` metrics so
  old telemetry handlers do not crash and detach after a bridge restart

## [0.2.0] - 2026-06-01

### Added

- added `Telemetry.Metrics.LastValue` support through OpenTelemetry observable
  gauges
- added `last_value` cardinality controls: `:ttl_ms`, `:max_series`, and
  `:on_overflow`
- expanded docs and the basic example with a bounded queue-depth `last_value`
  metric

### Changed

- relaxed the `telemetry_metrics` dependency to support both `~> 0.6` and
  `~> 1.0`

## [0.1.2] - 2026-05-30

### Changed

- rewrote the README and primary module docs to introduce the library from
  problem statement through integration flow
- added a lightweight architecture diagram and explicit metric mapping
  reference for the Telemetry-to-OpenTelemetry bridge
- improved module reference docs for `OtelBridge`, specs, profiles, and runtime
  internals with more consistent wording and onboarding guidance
- simplified ExDoc navigation by showing full module names instead of nested
  prefix shorthands

## [0.1.1] - 2026-05-30

### Changed

- expanded HexDocs coverage across all library modules
- documented public API functions, profiles, runtime modules, and behaviours
- improved HexDocs navigation with module grouping and nested namespaces
- added `source_url`, maintainer, and package links metadata
- added `ex_doc` as the documentation dependency for local and HexDocs builds

## [0.1.0] - 2026-05-30

### Added

- initial public `OtelBridge` supervision entrypoint
- `OtelBridge.Spec` behaviour and `use` helper
- `OtelBridge.Bridge` for `Telemetry.Metrics` to OpenTelemetry metrics bridging
- `OtelBridge.Profile` abstraction
- `OtelBridge.Profile.VictoriaMetrics` profile with cumulative temporality for
  synchronous metrics
- `OtelBridge.Exporter` for OTLP metrics export
- initial README, examples, and contract tests
