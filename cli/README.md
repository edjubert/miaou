# miaou

Track Mistral Vibe CLI usage (tokens, requests, estimated cost) from local
session journals, in the spirit of [Claude God](https://github.com/Lcharvol/Claude-God),
but reading only local files (no credentials, no undocumented APIs).

## DISCLAIMER: local data only, desynchronized from Mistral

Everything reported here is computed from the **local session journals**
written by the Vibe CLI on **this machine**. It is an observation of what
ran locally, not the account-wide truth.

- Usage on other machines, in Vibe on the web, in the IDE plugin or on
  mobile is **not** counted.
- Mistral exposes **no public, documented endpoint** to fetch account
  consumption. The only account-wide source is the Mistral Console web UI.
- Server-side billing may differ from these numbers (batching, rounding,
  what counts as a request, plan-specific accounting).
- The remaining plan envelope cannot be known locally: the monthly budget
  thresholds used by `budget` are observed or manually configured values,
  not server data.

The Mistral Console remains the authoritative source for billing. This
tool reads no credentials and calls no undocumented API.

```
cargo install --path .
miaou summary
```

## What it reads

```
$VIBE_HOME/logs/session/unified/<session-id>/
├── meta.json        # session metadata: cwd, start/end time, parent, title
└── journal/*.jsonl  # append-only records with a global `sequence`
```

- Model usage lives in `action_result` records whose
  `payload.result.type == "completion_succeeded"`
  (`payload.result.result.usage`: input/output/cached/total tokens).
- Journal records carry no timestamp; `core_input` records do
  (`payload.input.determinism.time_unix_ms`). Usage timestamps are
  interpolated from the nearest anchor by sequence, falling back to the
  session start time.
- Completions echoed inside `core_input` records are ignored, so each model
  call is counted exactly once.

## Commands

```
miaou summary              # totals + per-day overview
miaou today                # today's totals
miaou daily [--days N]     # per-day breakdown
miaou monthly [--months N] # per-month breakdown (each month starts at zero)
miaou projects             # per-project breakdown (session cwd basename)
miaou plan                 # plan type from Vibe's whoami cache
miaou budget [--init]      # month-to-date usage vs plan budget
miaou sessions             # per-session breakdown
miaou events               # raw events (one line per model call)
miaou watch [--interval S] # re-scan and print a line on change
```

Global flags: `--json`, `--since 2026-09-01`, `--until 2026-09-30`,
`--model <alias|name>`, `--vibe-home <path>` (default `$VIBE_HOME` or `~/.vibe`).

## Cost estimation

Journals do not record which model served a completion, so cost is an estimate
attributed to one model:

- `--model`, else the `active_model` from `~/.vibe/config.toml`;
- prices come from the matching `[[models]]` entry
  (`input_price`, `output_price`, `cached_input_price`, USD per million tokens);
- missing `cached_input_price` bills cached tokens at `input_price`;
- `input_tokens` is assumed to include cached tokens (observed:
  `total = input + output`, cached is a subset of input).

With no price declared for the model, the cost column shows `-` and tokens
remain the source of truth. Plan-based usage (e.g. Vibe Pro) is not billed per
token anyway.

## Plan information

`miaou plan` reads `~/.vibe/whoami_cache.json`, the local cache Vibe
maintains for its own `/whoami` command (TTL ~6h, refreshed by Vibe). No
network call, no credentials. The plan type vocabulary (`api` / `chat` /
`mistral_code`) matches Vibe's `AccountPlanKind`. Run `/whoami` in Vibe once
if the cache does not exist yet. `summary` also shows the plan.

## Budget

`miaou budget` compares month-to-date usage against a monthly envelope.

Threshold resolution order:

1. `~/.config/miaou/config.toml` (create with `miaou budget --init`,
   or point at another file with `--config PATH`). This file always wins.
2. Hardcoded plan defaults deduced from the whoami cache (Pro/INDIVIDUAL:
   $255/month of Vibe usage, an observed value, not an official limit).

```toml
[budget]
monthly_usd = 255.0    # plan envelope, in the calibration currency
overage_usd = 50.0      # extra PAYG allowance, only granted when:
overage_allowed = true # usage beyond the envelope is permitted
# monthly_tokens = 50_000_000  # optional token ceiling

[display]
currency = "EUR"       # symbol shown on costs: EUR -> €, USD -> $
```

The effective ceiling is `monthly_usd + overage_usd` when `overage_allowed`
is true, else `monthly_usd`. The command reports the used share, remaining
amount, whether usage sits in the overage allowance (PAYG) or beyond the
effective ceiling. Cost tracking requires model prices in Vibe's
`config.toml` (`[[models]] input_price`/`output_price`); without prices the
token ceiling applies instead.

**Currency**: the `monthly_usd` field name is historical; the value is in
whatever currency the prices and the calibration observations share. Keep
one currency across the whole chain: prices, envelope and Console
observations. The `[display] currency` setting only changes the symbol
shown.

## Calibrating per-token prices

Mistral does not publish the hosted rate for every model (verified for
`zai-glm-5-3` in September 2026). Two tracks:

1. **Lookup**: Console pricing page or invoice line items. Authoritative
   when available.
2. **Calibration** against the Console usage page, using the `calibrate`
   subcommands:

```
miaou calibrate add --at "2026-09-28T09:36:00Z" --cost 2.36
miaou calibrate list
miaou calibrate solve
```

Each observation pairs a Console month cost with the local token mix at the
same instant. The fit runs on **deltas between consecutive observations**
(`cost_i - cost_{i-1} = d_in*A + d_cached*B + d_out*C`), because the month
total includes usage that never touched this machine (web, mobile, remote
agents, pruned sessions) and would bias an absolute fit. Protocol:

- The Console displays UTC+2; `--at` takes UTC (convert the displayed
  boundary). There is no ingestion latency: the period end is the read
  time.
- Console costs do NOT track local tokens linearly: usage invisible to
  the local journals (IDE plugin, other surfaces) varies per window, so
  per-window rates swing from ~0.12 EUR/M (pure local) to ~1.65 EUR/M
  (heavy invisible usage). A per-token price fit is therefore not
  identifiable from console pairs.
- Working design: the budget anchors on the latest observation cost and
  values the tokens consumed since at the incremental rate of the most
  recent observation pair. Each `calibrate add` re-anchors and refines
  the rate.
- Keep the display currency identical across observations.

The tracker bills with the convention "cached tokens are a discounted part
of input": `cost = (in - cached) * input_price + cached * cached_input_price
+ out * output_price`.

## Monthly reset semantics

There is no deletion or explicit reset: `monthly` buckets usage by local
calendar month (`YYYY-MM`), so each month naturally starts at zero while the
full history stays queryable. Use `--since`/`--until` for arbitrary windows.
If a plan resets on a different day, filter with `--since 2026-09-28`.

## Known limits

- Model name per completion is not in the journals, so cost is an estimate
  attributed to the configured model.
- Only what ran on this machine: sessions on other machines, Vibe on web or
  the mobile app are invisible (see the disclaimer above and the Mistral
  Console for account-wide usage).
- Vibe may prune old sessions; the journals under `$VIBE_HOME` are the archive.
