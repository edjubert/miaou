# VibeGod

Monitor Mistral Vibe usage from the **macOS menu bar**, in the spirit of
[Claude God](https://github.com/Lcharvol/Claude-God), but reading only local
data (no credentials, no undocumented APIs).

## Architecture

```
Vibe sessions (~/.vibe/logs/session/unified/)
        │
        ▼
vibe-god-cli (Rust, local binary)      https://github.com/edjubert/vibe-god-cli
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

Scaffold. The backend (`vibe-god-cli`) is functional and tested; frontend
work starts here.
