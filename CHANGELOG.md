# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog and the project follows Semantic
Versioning.

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
