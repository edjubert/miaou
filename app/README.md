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
is a consumer of its JSON output (and may ship/embed the binary).

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

## Status

Milestone 1: menu bar app (Swift Package, `MenuBarExtra`) showing the
month-to-date budget, today's usage and quick commands, polling
`vibe-god-cli` every 60 s.

```bash
swift build && swift run
```

Requires `vibe-god-cli` in PATH (private repo: `cargo install --git
ssh://git@github.com/edjubert/vibe-god-cli.git`). Without model prices
configured, the bar shows month tokens instead of a cost percentage.

Structure: `Sources/VibeGod` (app + CLI bridge), `Sources/VibeGodTests`
(decode tests against vibe-god-cli JSON). No `.xcodeproj`: the package can
be adopted into an Xcode app bundle later for login-at-startup and
notarization.
