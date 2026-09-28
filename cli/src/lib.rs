//! vibe-god: track Mistral Vibe CLI usage from local session journals.
//!
//! Data model (as observed in `$VIBE_HOME/logs/session/unified/<session-id>/`):
//! - `meta.json` holds session metadata (cwd, start/end time, parent, title).
//! - `journal/*.jsonl` are append-only records with a global `sequence` number.
//!   - `action_result` records whose `payload.result.type == "completion_succeeded"`
//!     carry the model usage in `payload.result.result.usage`.
//!   - `core_input` records carry `payload.input.determinism.time_unix_ms`,
//!     used as time anchors to interpolate timestamps for usage records.

pub mod aggregate;
pub mod dates;
pub mod journal;
pub mod prices;
pub mod scan;

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

/// Scan all sessions under `<vibe_home>/logs/session/unified/` and extract usage.
pub fn collect_all(vibe_home: &Path) -> Vec<SessionUsage> {
    discover_sessions(vibe_home)
        .into_iter()
        .map(|(meta, dir)| {
            let events = parse_session(&dir, &meta);
            SessionUsage { meta, events }
        })
        .collect()
}
