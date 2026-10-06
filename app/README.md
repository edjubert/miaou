# VibeGod

Monitor Mistral Vibe usage from the **macOS menu bar**, in the spirit of
[Claude God](https://github.com/Lcharvol/Claude-God), but reading only local
data (no credentials, no undocumented APIs).

## DISCLAIMER: local data only, desynchronized from Mistral

Every number shown in the menu bar comes from `vibe-god-cli`, which reads
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
vibe-god-cli (Rust, local binary)      edjubert/vibe-god-cli (private repo)
        │  summary --json / budget --json / daily --json / ...
        ▼
VibeGod (SwiftUI menu bar app, this repo)
```

The CLI is the single source of truth for parsing and aggregation; this app
is a consumer of its JSON output and bundles a copy of the binary inside
`VibeGod.app`.

## Install

`make install-app` builds and installs the app, but it does not build
`vibe-god-cli` (private repo, SSH access required). The CLI binary is
embedded into the bundle at build time, so it must be on the machine
once, in `PATH` or `~/.cargo/bin`. After that the installed app is
self-contained and no longer depends on the CLI install.

From scratch:

```bash
# Prerequisites: Xcode Command Line Tools (swift), Rust (cargo)
# 1. Build and install the CLI (single source of truth for parsing)
cargo install --git ssh://git@github.com/edjubert/vibe-god-cli.git
# 2. Build and install the app (embeds the CLI into VibeGod.app)
git clone git@github.com:edjubert/VibeGod.git
cd VibeGod && make install-app
```

`make install-app` builds, bundles and installs to
`~/Applications/VibeGod.app`. Launch it from there, then enable
"Lancer au démarrage" in its settings (uses SMAppService and requires
the installed .app, not `swift run`).

Dev: `swift build && swift run` (uses the CLI from `~/.cargo/bin` or
`/opt/homebrew/bin`, not the embedded copy).

## Planned features

| Area | Feature |
|---|---|
| Menu bar | Month-to-date cost/tokens vs budget, refresh interval |
| Quotas | Progress bar against the plan envelope (see vibe-god-cli budget) |
| Analytics | Daily/weekly sparkline, per-project and per-session breakdown |
| Alerts | Notification when approaching the envelope or entering PAYG overage |
| Live | Detect active Vibe sessions (session locks under ~/.vibe/logs/session/active) |

## Roadmap

- macOS (SwiftUI, menu bar) first.
- Linux/Wayland equivalent later (tooling TBD: a Wayland bar widget via
  wlr-foreign-toplevel or a status-command for waybar/i3-style bars).

The data layer being shared, the Linux variant should reuse `vibe-god-cli`
as-is.

## Settings

The menu window has a "Barre de menu" section with a segmented picker:
**Coût** (month-to-date cost), **Pourcentage** (share of the effective
envelope) or **Les deux** (`€68.75 (27%)`). The choice persists in
`UserDefaults` (key `barMode`). Without cost estimation, all modes fall
back to month tokens. A `•` suffix marks live sessions.

## Status

Milestone 2: menu bar app consuming the single `vibe-god-cli dashboard`
JSON endpoint. Bar shows the envelope percentage (tokens fallback) plus a
live-session dot; the window shows budget progress, today's usage, a
14-day token sparkline (Swift Charts), top-5 projects and quick commands.
Refreshes every 60 s and on menu open. The CLI binary is looked up in
the app bundle first (embedded by `make app`), then `~/.cargo/bin` and
Homebrew paths: GUI processes inherit a minimal PATH.

The bundle carries LSUIElement (no Dock icon). Structure:
`Sources/VibeGod` (app + CLI bridge), `Sources/VibeGodTests`
(decode tests against vibe-god-cli JSON). No `.xcodeproj`: the package
can be adopted into an Xcode app bundle later for login-at-startup and
notarization.
