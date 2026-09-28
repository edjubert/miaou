# vibe-god

Track Mistral Vibe CLI usage from local session journals — tokens, requests and
estimated cost — in the spirit of [Claude God](https://github.com/Lcharvol/Claude-God),
but reading only local files (no credentials, no undocumented APIs).

```
cargo install --path .
vibe-god summary
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
vibe-god summary              # totals + per-day overview
vibe-god today                # today's totals
vibe-god daily [--days N]     # per-day breakdown
vibe-god monthly [--months N] # per-month breakdown (each month starts at zero)
vibe-god projects             # per-project breakdown (session cwd basename)
vibe-god sessions             # per-session breakdown
vibe-god events               # raw events (one line per model call)
vibe-god watch [--interval S] # re-scan and print a line on change
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

## Monthly reset semantics

There is no deletion or explicit reset: `monthly` buckets usage by local
calendar month (`YYYY-MM`), so each month naturally starts at zero while the
full history stays queryable. Use `--since`/`--until` for arbitrary windows.
If a plan resets on a different day, filter with `--since 2026-09-28`.

## Known limits

- Model name per completion is not in the journals — cost is an estimate
  attributed to the configured model.
- Only what ran on this machine: sessions on other machines, Vibe on web or
  the mobile app are invisible (see Mistral Console for account-wide usage).
- Vibe may prune old sessions; the journals under `$VIBE_HOME` are the archive.
