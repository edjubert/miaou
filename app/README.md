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

Dev: `swift build --manifest-cache none && swift run --manifest-cache none`
(uses the CLI from `~/.cargo/bin` or
`/opt/homebrew/bin`, not the embedded copy).

## Desktop cat (experimental)

Enable **Settings → Desktop cat → Show the cat along the bottom of the screen**.
The companion follows the selected Chaton/Le Chonk icon style and rests
gray and asleep along the bottom of the selected screen. It stays visible when the
main window closes, and clicks pass through it.

**Screen** offers **Primary** (the macOS primary display, default), **Built-in**
(the Mac's integrated display), and **Both**. Both shows one companion on each
of those displays; if they are the same display, only one cat appears.
When the built-in display is unavailable, the cat falls back to the primary
display. Selection applies live and persists across launches. Connecting,
disconnecting or rearranging displays updates the companions automatically.
Each cat has its own path, direction and random resting pauses. With both
displays selected, initial positions and directions are chosen independently.
Hovering one cat does not affect the other. Speech
bubbles appear together on the selected displays for the same five seconds.

**Size** offers S (140 points wide), M (200 points) and L (280 points).
M is the default and preserves the original size. Height follows the selected
pet's proportions. Changes apply live and persist without restarting the
current walk; hops and screen bounds follow the chosen dimensions.

The dot outline surrounds a transparent glass body: Liquid Glass on macOS 26,
with a native blur fallback on earlier versions. **Glass intensity** adjusts
the glass effect live, from no glass at 0% on the left to its full native
appearance at 100% on the right.
The slider fades only the glass, keeping the dot outline visible, and its value
persists across launches. It defaults to 100% to preserve the current appearance.
The native material still controls its own blur and refraction.
Hovering the cat makes
its glass body transparent and triggers a sideways hop, even while sleeping.
The hop rises by half the cat's height, lands one cat-width away within the
screen bounds, and immediately starts walking to the corner in that direction.
At the corner, it lies down. A continuous hover
triggers one hop; move away and hover again to trigger another.
The dots remain visible and clicks still pass through it.
**Color while moving** is enabled by default: dots use brand colors during hops
and walks, even without a live session, and turn gray when the pet reaches the
edge and lies down. Turn this color option off to keep the pet gray.
The desktop cat has its own **Animation** setting, independent of the menu bar:
**Always** walks automatically even without a session; **When a session is
active** (the default) only starts automatic walks during live sessions.
Automatic walks pause for 40–120 seconds at each edge. When session mode loses
its last session, the pet finishes its current trip to the edge and stays
asleep until another session or hover. Hover remains responsive in both modes.
Switching Chonk back to Chaton when a session ends preserves the current trip.
**Show the last message in a speech bubble** is optional and off by default.
It shows a short plain-text excerpt (up to 280 characters) of the latest
completed answer among active Vibe sessions. Each new completion appears once
for five seconds, and a new answer replaces the current bubble with a fresh
five-second duration. The bubble follows the cat, points toward it, stays
within the screen, and lets clicks pass through. Closing a session does not
shorten the five-second display; turning the option off hides it immediately.
Its background uses the same Liquid Glass (or native blur fallback) and glass
intensity as the cat. Small square dots in the cat's yellow-to-red palette form
the stepped border and pointer; the title and message use a monospace font.
Only completed text answers (`finish_reason: stop`) are used, excluding tool
calls, streaming responses and failed completions. Active journals are checked
every two seconds on a background queue and unchanged files are cached.
Previously active sessions remain readable for ten seconds after closing, to
catch a final answer flushed just after the lease disappears. Already displayed
answers from other sessions never block a new completion.
Text stays in memory; no model call, archive or widget export is involved.
Turn **Show the cat along the bottom of the screen** off to hide the companion.

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

A second widget, **Chaton**, only shows the animated cat in small and medium
formats. Choose **Chaton** or **Le Chonk** in its **Cat** setting. Existing
widgets keep Chaton by default. Its configuration offers two animation modes:
**Always** loops the animation forever, **When a session is active** animates
while a Vibe session is live (same activity signal as the green dot above) and freezes the cat on
its rest pose otherwise. The **Colors** setting offers **By session** (brand
colors while active, grayscale when idle), **Always in color**, and
**Grayscale**, independently of the animation mode. By session remains the
default for existing widgets. The widget shares the menu banner's animation clock:
poses advance every 0.16 s and pause for 40 s to 2 min on each cat's rest pose
(the sleeping Chaton or the lying Chonk). WidgetKit
receives 15 minutes of pose changes ahead of time, without crossfades between
poses. Refreshing the widget or reopening the menu preserves the current
pose and the remaining pause.
Both sizes use a minimal inset so the selected cat fills the available width.

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

**Show in menu bar** controls the entire menu bar item, independently of
**Show in Dock**. Turn it off to hide both the icon and text while the desktop
cat and widgets keep working. The choice persists across launches; reopen
Miaou's main window to enable it again.

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
