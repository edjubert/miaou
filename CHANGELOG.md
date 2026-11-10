# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.6.6] - 2026-11-10

### Added

- Desktop cat end-of-session setting: sleep immediately in place or walk to
  the nearest screen edge before sleeping (default), turning around if needed.
- Animated cat SVG exports in `chaton.svg` and `chaton-carre.svg`.

### Fixed

- Restore the CLI's `status` subcommand used by the app's activity polling.
- Session activity follows Vibe's explicit turn state: completed, failed and
  interrupted ACP tasks stop counting as active even when their server keeps
  the session lease. Resumed and long-running tasks remain detectable.
- The app checks activity every two seconds without rescanning usage history.
  Older dashboard responses cannot restore a task already reported as finished.
- App builds embed the CLI rebuilt from the same checkout by default, instead
  of silently using an older globally installed binary.
- App builds and installs validate the selected CLI's activity detection,
  including explicit `CLI_BIN` artifacts, before replacing the installed app.

## [0.6.5] - 2026-11-09

### Added

- Projects are grouped by git remote when the session's working directory is a
  git repo (key `host/owner/repo`), with the raw remote URL and the linked
  worktree paths shown per project; non-git directories keep the basename.
- The Months view shows the full monthly history, not just the plan month.
- Desktop cat: pet selector (Chaton / Le Chonk) independent of the menu bar
  icon, color mode (Session / Always / Grayscale), per-screen-kind bottom
  offset sliders (-10..+10 pt) and a walking speed slider (10..120 pt/s).
- Speech bubble: own glass intensity slider (full Liquid Glass by default) and
  border dots matching the cat's pixel size and spacing.

### Changed

- The desktop cat walks on the physical bottom edge of each screen, so its
  position is identical on every display regardless of Dock or DPI.
- Dot grids snap to whole device pixels per screen scale, so small sizes keep
  a visible margin between pixels; the glass backdrop is clipped to the dot
  outline and no longer sticks out past the pet.
- A message wrapped in FEATURE_NAME markers is shown as a small gray
  "Renamed session:" label above the white output; the "Vibe session" title is
  hidden for those messages.

### Fixed

- Session liveness: ACP-held leases (user sessions driven through ACP) count as
  active again; only vibe-app-server leases are excluded, now matched on the
  full command line since the Vibe tools are Python scripts.

## [0.6.4] - 2026-11-09

### Added

- Desktop cat pet selector: Chaton or Le Chonk for the desktop companion,
  independent of the menu bar icon.
- Desktop cat color mode: Session (default), Always, or Grayscale, replacing
  the "color while moving" toggle.
- Speech bubble glass intensity slider; the bubble keeps its Liquid Glass
  background by default.

### Changed

- The speech bubble's border dots match the desktop cat's pixel size and
  spacing at every size.

## [0.6.3] - 2026-11-09

### Fixed

- Desktop cat dots keep a visible margin at every size: the dot grid snaps to
  whole device pixels with a gap of at least two device pixels, so the small
  size no longer merges adjacent pixels.
- The desktop cat's glass backdrop no longer sticks out past the pet: it is
  clipped to the dot outline and only fills the gaps between dots.

## [0.6.2] - 2026-11-08

### Fixed

- The desktop cat no longer falls asleep when it reaches a screen edge while a
  session is active or while animation is set to always. It only sleeps at an
  edge when no task is in progress; otherwise it turns around and keeps walking.

## [0.6.1] - 2026-11-08

### Added

- Desktop cat screen selector: Primary (default), Built-in, or Both, applied
  live and remembered across launches. Each selected display has its own cat
  and synchronized speech bubble. Display changes update placement automatically;
  unavailable built-in displays fall back to the primary display, and selecting
  Both never duplicates the cat when primary and built-in are the same display.

### Changed

- Hovering the desktop cat keeps its glass background at the selected intensity.
  The hover still triggers a hop and an independent walk toward a screen edge.

## [0.6.0] - 2026-11-07

### Added

- Optional speech bubble above the desktop cat: show a short excerpt of the
  newest completed answer among active or just-closed Vibe sessions for five
  seconds, once per message. The bubble follows the cat and stays within the
  screen. Journal reads run in the background; unfinished and tool-call
  completions are ignored.
- Desktop companion size selector: S, M (the current size, default), or L.
  Changes apply live, persist, and preserve the current walk.

### Changed

- Desktop speech bubbles match the cat with a Liquid Glass background,
  a stepped square-dot border in brand colors and monospace text. The cat's
  glass intensity slider also controls the bubble's background.

### Fixed

- Closing a Vibe session no longer hides its final speech bubble early or
  drops an answer flushed just after the session closes. Bubbles remain visible
  for their full five seconds, and already shown replies from other sessions
  cannot hide a new completion.

## [0.5.0] - 2026-11-07

### Changed

- The menu bar and widget pets' sleeping pause lasts a random 40 s to 2 min
  instead of a random 5–20 s.
- The main window's liquid glass cards use the clearest glass variant
  (`.clear` on macOS 26+, `.ultraThinMaterial` before), so the background
  shows through more.
- New **Animation** setting in the app's icon settings: the menu bar pet
  animates **Always** or only **When a session is active** (the default,
  its previous behavior).
- The desktop companion stays gray at rest. Hovering wakes it for a
  hop and a walk to a bottom corner.
  A separate color setting allows brand colors during movement even without an
  active session.

### Added

- New **Show in menu bar** setting hides the entire menu bar item, independently
  of Dock visibility, without stopping the desktop companion or widgets.
- Independent **Animation** setting for the desktop companion: automatic walks
  always or only during active sessions (default), with 40–120 second pauses at
  screen edges. Hover stays responsive in both modes. When the last session
  ends, session mode finishes the current walk and then stays asleep.
- New **Glass intensity** slider for the desktop companion: fade the glass
  effect live from its full native appearance to completely hidden, keeping the
  dot outline visible. The setting persists and hovering still hides the glass.
  No glass is 0% on the left and the full glass effect is 100% on the right.
- Restore the desktop companion alongside the widget and menu bar settings.
  Its enablement persists across app upgrades.
- New **Show in Dock** setting: turn it off to hide Miaou's Dock icon and
  run as a menu-bar-only app (activation policy `.accessory`).
- Hovering the desktop companion makes it hop aside, rising by half its height
  and walking to a corner after landing, even when it was sleeping. Its glass body
  becomes transparent while hovered, keeping the dots visible and
  letting clicks pass through.

### Fixed

- Switching the desktop pet between Chaton and Chonk when a session starts or
  ends preserves its current trip to the screen edge instead of resetting it.
- `miaou dashboard` no longer runs synchronously on the main thread. The
  lock watcher fires exactly when a session ends (when the pet freezes),
  and a slow CLI call was blocking the menu bar for the whole subprocess.
- Installation unregisters all older widget copies, including superseded
  or disabled entries, before registering the installed extension.
- Installation rejects a widget signed with the restricted host entitlement
  `com.apple.private.chrono-extension-host`: static signature verification
  accepts it, but macOS refuses to launch it without an Apple provisioning profile.

## [0.4.0] - 2026-11-06

### Added

- Native main window with a sidebar for graphs, projects and settings,
  metric cards, tables, and a refresh action.
- Le Chonk in the menu bar and banner, selected automatically when Vibe's
  active model is Le Chonk or manually in the app's icon settings.
- Desktop widget **Chaton** (small and medium): shows only the animated cat,
  with a choice of **Chaton** or **Le Chonk** and a parameter to animate always
  or only while a Vibe session is active; brand colors while active, grayscale
  otherwise.
- The pet widget's **Colors** setting offers session-based colors, always
  in color, or grayscale, independently of the animation mode.

### Changed

- The menu bar focuses on budget, today's usage and active sessions;
  per-session folds show metadata and unfold on hover.

### Fixed

- Session activity requires both a held lease and recent metadata;
  leases held by `vibe-app-server` no longer count as active sessions.
- App settings use working native pickers and a grouped form.
- The Chaton widget shares the menu banner's 0.16 s animation steps and
  5–20 s sleeping pauses. Timeline refreshes preserve its pose and pause,
  and pose changes no longer use implicit crossfade transitions.
- Widget configuration labels resolve the app's English and French
  catalogs instead of displaying raw localization keys.
- Chaton and Le Chonk fill more of their widget: automatic content
  margins are disabled and internal padding is reduced.
- The always-on animation uses compact vector paths so macOS can accept
  its timeline archive instead of rejecting it as too large.

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
