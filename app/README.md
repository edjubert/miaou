# Miaou

Monitor Mistral Vibe usage from the **macOS menu bar**, in the spirit of
[Claude God](https://github.com/Lcharvol/Claude-God), but reading only local
data (no credentials, no undocumented APIs).

## DISCLAIMER: local data only, desynchronized from Mistral

Every number shown in the menu bar comes from `miaou`, which reads
the **local session journals** of this machine. It is not the account-wide
truth: usage from other machines, Vibe on the web, the IDE plugin or mobile
is not counted, and Mistral exposes no public endpoint to fetch account
consumption. The Mistral Console web UI is the only authoritative source
for billing, and it may differ from these numbers. The remaining plan
envelope cannot be known locally (thresholds are observed or manually
configured values, not server data).

## Architecture

```
Vibe sessions (~/.vibe/logs/session/unified/)
        │
        ▼
miaou (Rust, local binary)      cli/ in this monorepo
        │  summary --json / budget --json / daily --json / ...
        ▼
Miaou (SwiftUI menu bar app, app/)
```

The CLI is the single source of truth for parsing and aggregation; this app
is a consumer of its JSON output and bundles a copy of the binary inside
`Miaou.app`.

## Install

`make -C app install-app` builds and installs the app, but it does not build
`miaou`: the CLI binary is embedded into the bundle at build time, so it
must be on the machine once, in `PATH` or `~/.cargo/bin`. After that the
installed app is self-contained and no longer depends on the CLI install.

From scratch (monorepo root):

```bash
# Prerequisites: full Xcode (app and widget), Rust (cargo), Python 3
git clone git@github.com:edjubert/miaou.git
cd miaou
# 1. Build and install the CLI (single source of truth for parsing)
cargo install --path cli
# 2. Build and install the app (embeds the CLI into Miaou.app)
make -C app install-app
```

Or release artifacts: `make release` produces `Miaou.app` plus `miaou`
binaries for macOS ARM and Linux.

`make install-app` builds, bundles and installs to
`~/Applications/Miaou.app`. Launch it from there, then enable
"Lancer au démarrage" in its settings (uses SMAppService and requires
the installed .app, not `swift run`).

Dev: `swift build && swift run` (uses the CLI from `~/.cargo/bin` or
`/opt/homebrew/bin`, not the embedded copy).

## Planned features

| Area | Feature |
|---|---|
| Menu bar | Month-to-date cost/tokens vs budget, refresh interval |
| Quotas | Progress bar against the plan envelope (see miaou budget) |
| Analytics | Daily/weekly sparkline, per-project and per-session breakdown |
| Alerts | Notification when approaching the envelope or entering PAYG overage |
| Live | Detect held Vibe session locks under ~/.vibe/logs/session/active; orphaned files and the cleanup lease are ignored |

## Roadmap

- macOS (SwiftUI, menu bar) first.
- Linux/Wayland equivalent later (tooling TBD: a Wayland bar widget via
  wlr-foreign-toplevel or a status-command for waybar/i3-style bars).

The data layer being shared, the Linux variant should reuse `miaou`
as-is.

## Desktop and Notification Center widget

The menu bar app supports macOS 13 or later. On macOS 14 or later, open the
installed Miaou app, use **Edit Widgets**, search for **Miaou**, and choose
the small, medium or large format.

| Size | Display |
|---|---|
| Small | Month cost (tokens fallback), budget progress and session activity |
| Medium | Month budget plus today's cost, requests and tokens |
| Large | Budget, remaining amount, today's metrics and a daily token chart |

Click the widget background to open the dashboard. The refresh button opens
Miaou and refreshes its data. The widget follows the app's language setting
and currency configuration.

The app publishes display metrics to a private App Group after each refresh.
The sandboxed widget reads that snapshot; it does not run the CLI or read Vibe
journals. Keep Miaou running for fresh figures. If it quits, the last snapshot
remains visible with its update age. Old session activity expires, and a new
calendar month asks you to reopen the app instead of showing the previous
month's spending as current. At midnight, daily metrics retain their date
until the app publishes the new day's figures.

WidgetKit controls refresh timing: Miaou requests another update after 60
seconds, and macOS may defer it. Desktop widget colors also follow macOS's
widget appearance settings.

The app bundle now builds with **full Xcode**, using native app and extension
targets. Swift Package Manager remains available for development and tests.
Both bundles use the same Apple signing identity and App Group. The builder
selects an available Apple Development identity automatically; override with:

```bash
SIGN_IDENTITY="Apple Development: Your Name (ID)" TEAM_ID=YOURTEAMID make -C app install-app
```

`APP_GROUP` can override the default `TEAM_ID.com.edjubert.miaou`.
`SIGN_IDENTITY=-` builds an ad-hoc development bundle; macOS widget activation
requires a valid Apple signing identity. The app and widget receive matching
build numbers, and installation unregisters older widget copies before
registering the installed extension.

## Settings

The menu window has a "Barre de menu" section with a segmented picker:
**Coût** (month-to-date cost), **Pourcentage** (share of the effective
envelope) or **Les deux** (`€68.75 (27%)`). The choice persists in
`UserDefaults` (key `barMode`). Without cost estimation, all modes fall
back to month tokens. A `•` suffix marks live sessions.

The UI ships in English and French. It follows the system language by
default; the segmented language picker in the settings forces
Français or English (key `language`), which also localizes month and
day names.

## Status

Milestone 2: menu bar app consuming the single `miaou dashboard`
JSON endpoint. Bar shows the envelope percentage (tokens fallback) plus a
live-session dot; the window shows budget progress, today's usage, a
14-day token sparkline (Swift Charts), top-5 projects and quick commands.
Refreshes every 60 s and on menu open. The CLI binary is looked up in
the app bundle first (embedded by `make app`), then `~/.cargo/bin` and
Homebrew paths: GUI processes inherit a minimal PATH.

When the CLI's calibration ledger holds a Console observation for the
current month, the month cost anchors on it (see the CLI README) and the
budget section shows the applied anchor: its cost and the time it was
recorded (`Ancre console : 190.05 € à 12 oct. 14:31`). The displayed
used amount is then anchor cost + local usage since, valued per session.

The "Console month cost" field and "Anchor" button above that line record
the Console's current month total in the displayed currency at the current
time. Submit with the button or Return; both `190.05` and `190,05` are
accepted. After saving, the dashboard and menu bar refresh automatically.

The bundle carries LSUIElement (no Dock icon). Structure:
`Sources/Miaou` (app + CLI bridge), `Shared` (widget snapshot, view and
refresh intent), `Widget` (WidgetKit extension), `Sources/MiaouTests`
(CLI decoding and widget tests). `build-app.py` generates the native
Xcode project under `.build/native-app`; it is not checked into Git.
