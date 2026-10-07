//! miaou: track Mistral Vibe CLI usage from local session journals.
//!
//! Data model (as observed in `$VIBE_HOME/logs/session/unified/<session-id>/`):
//! - `meta.json` holds session metadata (cwd, start/end time, parent, title).
//! - `journal/*.jsonl` are append-only records with a global `sequence` number.
//!   - `action_result` records whose `payload.result.type == "completion_succeeded"`
//!     carry the model usage in `payload.result.result.usage`.
//!   - `core_input` records carry `payload.input.determinism.time_unix_ms`,
//!     used as time anchors to interpolate timestamps for usage records.

pub mod archive;
pub mod aggregate;
pub mod budget;
pub mod calibrate;
pub mod dates;
pub mod journal;
pub mod plan;
pub mod prices;
pub mod scan;
pub mod status;

pub use aggregate::{aggregate_by_period, aggregate_by_project, aggregate_by_session, aggregate_daily, aggregate_monthly, Totals};
pub use journal::{parse_session, UsageEvent};
pub use scan::{discover_sessions, SessionMeta};

use std::path::{Path, PathBuf};

/// A session plus its extracted usage events.
#[derive(Debug, Clone)]
pub struct SessionUsage {
    pub meta: SessionMeta,
    pub events: Vec<UsageEvent>,
}

impl SessionUsage {
    pub fn totals(&self) -> Totals {
        Totals::from_events(self.events.iter())
    }
}

/// Resolve the default Vibe home (`$VIBE_HOME` or `~/.vibe`).
pub fn default_vibe_home() -> PathBuf {
    std::env::var_os("VIBE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            let home = std::env::var_os("HOME").unwrap_or_default();
            Path::new(home.as_os_str()).join(".vibe")
        })
}

/// Build the usage dataset: live journals are ingested into the append-only
/// archive (`archive::merged_sessions`), so history survives Vibe's journal
/// compaction and session pruning.
pub fn collect_all(vibe_home: &Path) -> Vec<SessionUsage> {
    archive::merged_sessions(vibe_home)
}

/// Like `collect_all`, with an explicit events-archive location (for tests).
pub fn collect_all_with_archive(vibe_home: &Path, archive: &Path) -> Vec<SessionUsage> {
    archive::merged_sessions_with(vibe_home, archive)
}

/// Restrict sessions to the events of a local calendar month (plan period),
/// dropping sessions that have nothing left. The dashboard is scoped to
/// the current month so every view resets with the plan.
pub fn scope_to_month(sessions: &[SessionUsage], ym: &str) -> Vec<SessionUsage> {
    sessions
        .iter()
        .filter_map(|s| {
            let events: Vec<UsageEvent> = s
                .events
                .iter()
                .filter(|e| dates::local_ym(e.timestamp_ms) == ym)
                .cloned()
                .collect();
            if events.is_empty() {
                None
            } else {
                Some(SessionUsage { meta: s.meta.clone(), events })
            }
        })
        .collect()
}
