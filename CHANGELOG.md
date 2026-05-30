# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog and the project follows Semantic
Versioning.

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
