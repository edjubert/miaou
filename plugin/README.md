# VibeGod plugin (vibe-god-plugin)

Mistral Vibe plugin that surfaces **usage tracking inside the Vibe TUI**,
powered by [`vibe-god-cli`](https://github.com/edjubert/vibe-god-cli).

Two integration points, following the Agent Plugins 1.0 format:

- a `post_agent` hook calling `vibe-god-cli` after each turn and emitting a
  short usage line (`system_message`) in the UI;
- a skill for on-demand reports (`/usage` style: today, budget, projects).

## Status

Scaffold. Built after the menu bar app (VibeGod) or whenever the in-TUI
display is wanted.
