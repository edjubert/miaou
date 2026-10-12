# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-10-12

### Added

- Daily chart hover: moving the cursor over a bar dims the others and shows a popover with the day and the exact token count.
- Localized short units on the daily chart y-axis: `M`/`B` in English, `M`/`Md` in French, instead of scientific notation.
- Per-session pricing with model attribution and USD to EUR conversion.

### Changed

- Daily chart: per-bar value labels and x-axis day labels are hidden; the details live in the hover popover.

### Fixed

- `calibrate add --at` accepts a local time without offset.

## [0.1.0] - 2026-10-07

First release: the fused monorepo (Rust CLI + macOS menu bar app).

### Added

- CLI (`miaou`) tracking Mistral Vibe usage (tokens, requests, estimated cost) from local session journals: `summary`, `daily`, `projects`, `sessions`, `events` and `watch` subcommands.
- Monthly aggregation with natural month reset.
- Monthly budget with plan defaults, manual config and PAYG overage display.
- Plan type exposed from Vibe's `whoami` cache.
- Price calibration against Mistral Console costs (`calibrate`).
- Configurable display currency, surfaced in the dashboard JSON.
- Append-only event archive with snapshot floor.
- `dashboard` JSON endpoint with active session detection.
- macOS menu bar app (Miaou.app): menu bar label with selectable display mode (cost, percentage, both, none), cat glyph icon colored by session liveness, green status dot for live sessions.
- In-app analytics window with daily/monthly/sessions tabs, budget section, today section and projects share bars.
- App bundle with launch-at-login support.
- UI localized in English and French, with an in-app language picker.
- Version badge in the menu footer.

### Notes

- Local data only: no credentials, no undocumented APIs. Other machines and surfaces are invisible to it.
