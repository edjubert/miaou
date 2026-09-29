//! Append-only archive of usage events.
//!
//! Vibe compacts session journals and deletes old records: history seen
//! once can disappear from the journals. The archive keeps every event
//! ever ingested, deduplicated by (session_id, sequence), so aggregations
//! survive compaction and session pruning. Events also record the project
//! name observed at ingest time, so sessions whose directory disappears
//! keep their project attribution.
//!
//! Stored at `~/.config/vibe-god-cli/events-archive.jsonl`.

use crate::scan::SessionMeta;
use crate::{SessionUsage, UsageEvent};
use std::collections::HashMap;
use std::path::PathBuf;

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, PartialEq)]
pub struct ArchivedEvent {
    pub session_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub parent_session_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub project: Option<String>,
    pub sequence: u64,
    pub timestamp_ms: u64,
    pub input_tokens: u64,
    pub output_tokens: u64,
    pub cached_input_tokens: u64,
    pub total_tokens: u64,
}

impl From<&UsageEvent> for ArchivedEvent {
    fn from(e: &UsageEvent) -> Self {
        ArchivedEvent {
            session_id: e.session_id.clone(),
            parent_session_id: e.parent_session_id.clone(),
            project: None,
            sequence: e.sequence,
            timestamp_ms: e.timestamp_ms,
            input_tokens: e.input_tokens,
            output_tokens: e.output_tokens,
            cached_input_tokens: e.cached_input_tokens,
            total_tokens: e.total_tokens,
        }
    }
}

impl ArchivedEvent {
    fn into_usage_event(self) -> UsageEvent {
        UsageEvent {
            session_id: self.session_id,
            parent_session_id: self.parent_session_id,
            sequence: self.sequence,
            timestamp_ms: self.timestamp_ms,
            input_tokens: self.input_tokens,
            output_tokens: self.output_tokens,
            cached_input_tokens: self.cached_input_tokens,
            total_tokens: self.total_tokens,
            finish_reason: String::new(),
        }
    }
}

pub fn archive_path() -> PathBuf {
    crate::budget::default_config_path()
        .parent()
        .map(|p| p.join("events-archive.jsonl"))
        .unwrap_or_else(|| PathBuf::from("events-archive.jsonl"))
}

/// Load the archive, deduplicating by (session_id, sequence) and keeping
/// the last occurrence. Concurrent runs appending the same events twice
/// are therefore harmless.
pub fn load(path: &std::path::Path) -> Vec<ArchivedEvent> {
    let raw = std::fs::read_to_string(path).unwrap_or_default();
    let mut map: HashMap<(String, u64), ArchivedEvent> = HashMap::new();
    for line in raw.lines() {
        let Ok(event) = serde_json::from_str::<ArchivedEvent>(line) else {
            continue;
        };
        map.insert((event.session_id.clone(), event.sequence), event);
    }
    let mut events: Vec<ArchivedEvent> = map.into_values().collect();
    events.sort_by_key(|e| (e.session_id.clone(), e.sequence));
    events
}

/// Append events new to the archive: for each session, everything with a
/// sequence above the archived watermark. Returns the number appended.
pub fn append_new(path: &std::path::Path, sessions: &[SessionUsage]) -> usize {
    let archived = load(path);
    let mut watermark: HashMap<&str, u64> = HashMap::new();
    for e in &archived {
        let entry = watermark.entry(e.session_id.as_str()).or_insert(0);
        if e.sequence > *entry {
            *entry = e.sequence;
        }
    }
    let mut appended = 0;
    let mut out = String::new();
    for s in sessions {
        let project = project_of(&s.meta);
        for e in &s.events {
            if e.sequence > *watermark.get(s.meta.session_id.as_str()).unwrap_or(&0) {
                let mut record = ArchivedEvent::from(e);
                record.project.clone_from(&project);
                out.push_str(&serde_json::to_string(&record).unwrap_or_default());
                out.push('\n');
                appended += 1;
            }
        }
    }
    if appended > 0 {
        use std::io::Write;
        if let Some(parent) = path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        if let Ok(mut file) = std::fs::OpenOptions::new().create(true).append(true).open(path) {
            let _ = file.write_all(out.as_bytes());
        }
    }
    appended
}

fn project_of(meta: &SessionMeta) -> Option<String> {
    meta.cwd
        .as_deref()
        .map(|c| c.rsplit('/').next().unwrap_or(c))
        .map(str::to_owned)
}

/// Build the full session list: archive events (complete history) with
/// live session metadata where the session still exists.
pub fn merged_sessions(vibe_home: &std::path::Path) -> Vec<SessionUsage> {
    let live = crate::scan::discover_sessions(vibe_home)
        .into_iter()
        .map(|(meta, dir)| {
            let events = crate::journal::parse_session(&dir, &meta);
            SessionUsage { meta, events }
        })
        .collect::<Vec<_>>();

    append_new(&archive_path(), &live);
    let archived = load(&archive_path());

    let mut live_meta: HashMap<String, SessionMeta> =
        live.iter().map(|s| (s.meta.session_id.clone(), s.meta.clone())).collect();

    let mut by_session: HashMap<String, Vec<UsageEvent>> = HashMap::new();
    for e in archived {
        by_session
            .entry(e.session_id.clone())
            .or_default()
            .push(e.clone().into_usage_event());
        // Remember project attribution for sessions that may disappear.
        if !live_meta.contains_key(&e.session_id) {
            live_meta
                .entry(e.session_id.clone())
                .or_insert_with(|| SessionMeta {
                    session_id: e.session_id.clone(),
                    cwd: e.project.clone().map(|p| format!("/{p}")),
                    title: None,
                    start_time_ms: None,
                    end_time_ms: None,
                    parent_session_id: e.parent_session_id.clone(),
                    child_sessions: Vec::new(),
                });
        }
    }

    let mut sessions: Vec<SessionUsage> = Vec::new();
    for (id, mut events) in by_session {
        events.sort_by_key(|e| e.sequence);
        let mut meta = live_meta.remove(&id).unwrap_or_else(|| SessionMeta {
            session_id: id.clone(),
            ..Default::default()
        });
        if meta.start_time_ms.is_none() {
            meta.start_time_ms = events.first().map(|e| e.timestamp_ms);
        }
        sessions.push(SessionUsage { meta, events });
    }
    sessions.sort_by_key(|s| s.meta.start_time_ms.unwrap_or(0));
    sessions
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::scan::SessionMeta;

    fn session(id: &str, seq: u64, tokens: u64) -> SessionUsage {
        SessionUsage {
            meta: SessionMeta {
                session_id: id.into(),
                cwd: Some("/work/proj-a".into()),
                start_time_ms: Some(1000),
                ..Default::default()
            },
            events: vec![UsageEvent {
                session_id: id.into(),
                parent_session_id: None,
                sequence: seq,
                timestamp_ms: 1000 + seq,
                input_tokens: tokens,
                output_tokens: 1,
                cached_input_tokens: 0,
                total_tokens: tokens + 1,
                finish_reason: "stop".into(),
            }],
        }
    }

    fn temp() -> std::path::PathBuf {
        tempfile::tempdir().unwrap().keep()
    }

    #[test]
    fn append_then_reload_without_duplicates() {
        let dir = temp();
        let archive = dir.join("archive.jsonl");
        let live = vec![session("a", 1, 100), session("a", 2, 200), session("b", 1, 50)];
        assert_eq!(append_new(&archive, &live), 3);
        // Re-ingesting the same sessions appends nothing.
        assert_eq!(append_new(&archive, &live), 0);
        let events = load(&archive);
        assert_eq!(events.len(), 3);
        assert!(events.iter().all(|e| e.project.as_deref() == Some("proj-a")));
    }

    #[test]
    fn archive_survives_journal_loss() {
        let dir = temp();
        let archive = dir.join("archive.jsonl");
        // First ingest: two sessions.
        let live = vec![session("a", 1, 100), session("b", 5, 900)];
        append_new(&archive, &live);
        // Compaction: session b's journal records disappear entirely.
        let shrunk = vec![session("a", 1, 100)];
        append_new(&archive, &shrunk);
        let events = load(&archive);
        let total: u64 = events.iter().map(|e| e.input_tokens).sum();
        assert_eq!(total, 1000, "b's history must survive in the archive");
    }
}
