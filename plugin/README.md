# Miaou plugin

Mistral Vibe plugin that surfaces **usage tracking inside the Vibe TUI**,
powered by the `miaou` CLI (`cli/` in this monorepo).

## DISCLAIMER: local data only

All figures come from the **local session journals** of the machine running
Vibe, via `miaou`. They are not the account-wide truth: Mistral
exposes no public endpoint to fetch account consumption, so anything that
ran elsewhere (other machines, Vibe web, IDE, mobile) is invisible here.
The Mistral Console web UI is the only authoritative billing source.

Two integration points, following the Agent Plugins 1.0 format:

- a `post_agent` hook calling `miaou` after each turn and emitting a
  short usage line (`system_message`) in the UI;
- a skill for on-demand reports (`/usage` style: today, budget, projects).

## Status

Scaffold. Built after the menu bar app (Miaou, `app/`) or whenever the
in-TUI display is wanted.
