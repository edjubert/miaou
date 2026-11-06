# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Desktop widget **Chaton** (small and medium): shows only the animated cat,
  with a configuration parameter to animate always or only while a Vibe
  session is active. The animation is a WidgetKit timeline of entries spaced
  0.16 s apart over one cycle; brand colors while active, grayscale on the
  rest pose otherwise.

## [0.3.0] - 2026-11-05

### Added

- Session rows expose `title_source` and an `active` flag (OS lock held) in
  `miaou sessions` and `miaou dashboard` JSON; the dashboard's `active` list
  also carries `title` and `title_source`.
- Menu bar app: sessions render as folds. Live sessions are labeled
  `titre title_source.  session_id`; hovering a row shows a metadata popover
  without flickering, clicking anywhere on a row toggles the fold, and
  clicking the id copies it to the pasteboard. The live section is a fold
  with a generic label showing the active session count.
- `make install` at the repo root builds the app and installs it into
  `~/Applications`.

### Fixed

- Budget config accepts integer USD amounts: `monthly_usd = 255` was silently
  dropped (only TOML floats were read), leaving the menu bar without a
  percentage once the plan cache no longer provided a default.
- Installing the app quits a running instance started from the installed
  bundle, so relaunching cannot keep serving the old binary from memory.

## [0.2.1] - 2026-11-02

### Added

- Native macOS desktop and Notification Center widget in three sizes, with
  monthly cost and budget, today's usage, session activity and a daily chart.
- Widget refresh action and dashboard link, localized in English and French.
- Console cost input to anchor the month's estimate on the latest observation.

### Changed

- App bundles build with native Xcode app and WidgetKit extension targets,
  sharing a signed App Group and matching build numbers.
- Installation registers the widget and removes obsolete extension candidates.
- App and CLI versions share a single source of truth.

### Fixed

- Session activity checks the held OS lock instead of the lock file's age,
  ignoring orphaned files after a process exits and Vibe's cleanup lease.
- Open sessions stay active even when their lock file is older than five minutes.
- Widget activity expires from the latest verified observation rather than
  the lock file's modification time.
- Console cost adjustment remains available before the first anchor.
- CLI subprocesses inherit the app's environment when no override is supplied.

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
