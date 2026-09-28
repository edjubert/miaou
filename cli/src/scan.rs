//! Session discovery: find `<vibe_home>/logs/session/unified/<uuid>/` dirs and
//! parse their `meta.json`.

use std::path::{Path, PathBuf};

/// Metadata from a session's `meta.json`.
#[derive(Debug, Clone, Default)]
pub struct SessionMeta {
    pub session_id: String,
    pub cwd: Option<String>,
    pub title: Option<String>,
    /// Session start, unix epoch milliseconds (derived from ISO-8601 `start_time`).
    pub start_time_ms: Option<u64>,
    pub end_time_ms: Option<u64>,
    /// Set when this session is a subagent run.
    pub parent_session_id: Option<String>,
    pub child_sessions: Vec<String>,
}

/// Discover all sessions, returning `(meta, session_dir)` pairs sorted by start time.
pub fn discover_sessions(vibe_home: &Path) -> Vec<(SessionMeta, PathBuf)> {
    let unified = vibe_home.join("logs").join("session").join("unified");
    let mut out = Vec::new();
    let Ok(entries) = std::fs::read_dir(&unified) else {
        return out;
    };
    for entry in entries.flatten() {
        let dir = entry.path();
        if !dir.is_dir() {
            continue;
        }
        let meta_path = dir.join("meta.json");
        if !meta_path.is_file() {
            continue;
        }
        let Ok(raw) = std::fs::read_to_string(&meta_path) else {
            continue;
        };
        let Ok(v) = serde_json::from_str::<serde_json::Value>(&raw) else {
            continue;
        };
        let meta = SessionMeta {
            session_id: v
                .get("session_id")
                .and_then(|x| x.as_str())
                .unwrap_or_default()
                .to_string(),
            cwd: v.get("environment").and_then(|e| e.get("working_directory")).and_then(|x| x.as_str()).map(str::to_owned)
                .or_else(|| v.get("origin_directory").and_then(|x| x.as_str()).map(str::to_owned)),
            title: v.get("title").and_then(|x| x.as_str()).map(str::to_owned),
            start_time_ms: iso_to_ms(v.get("start_time").and_then(|x| x.as_str())),
            end_time_ms: iso_to_ms(v.get("end_time").and_then(|x| x.as_str())),
            parent_session_id: v
                .get("parent_session_id")
                .and_then(|x| x.as_str())
                .filter(|s| !s.is_empty())
                .map(str::to_owned),
            child_sessions: v
                .get("child_sessions")
                .and_then(|x| x.as_array())
                .map(|a| a.iter().filter_map(|x| x.as_str().map(str::to_owned)).collect())
                .unwrap_or_default(),
        };
        out.push((meta, dir));
    }
    out.sort_by_key(|(m, _)| m.start_time_ms.unwrap_or(0));
    out
}

/// Parse a subset of ISO-8601 (`2026-09-28T13:26:02.137000+00:00`) into epoch ms.
fn iso_to_ms(s: Option<&str>) -> Option<u64> {
    let s = s?;
    chrono::DateTime::parse_from_rfc3339(s)
        .ok()
        .map(|dt| dt.timestamp_millis().max(0) as u64)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn iso_parsing() {
        assert_eq!(
            iso_to_ms(Some("2026-09-28T13:26:02.137000+00:00")),
            Some(1790601962137)
        );
        assert_eq!(iso_to_ms(Some("garbage")), None);
        assert_eq!(iso_to_ms(None), None);
    }
}
