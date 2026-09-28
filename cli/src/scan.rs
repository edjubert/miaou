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

    fn write_session(unified: &Path, id: &str, meta_json: &str) {
        let dir = unified.join(id);
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("meta.json"), meta_json).unwrap();
    }

    #[test]
    fn discovers_and_sorts_sessions() {
        let tmp = tempfile::tempdir().unwrap();
        let unified = tmp.path().join("logs").join("session").join("unified");
        std::fs::create_dir_all(&unified).unwrap();

        write_session(
            &unified,
            "newer",
            r#"{"session_id": "newer",
                "environment": {"working_directory": "/home/me/proj-a"},
                "start_time": "2026-09-28T13:00:00+00:00",
                "end_time": "2026-09-28T14:00:00+00:00",
                "parent_session_id": null,
                "child_sessions": ["kid-1"],
                "title": "Some title"}"#,
        );
        write_session(
            &unified,
            "older",
            r#"{"session_id": "older",
                "environment": {"working_directory": "/home/me/proj-b"},
                "start_time": "2026-09-27T09:00:00+00:00",
                "parent_session_id": "some-parent",
                "child_sessions": []}"#,
        );
        // Decoys: no meta.json, not a directory.
        std::fs::create_dir(unified.join("no-meta")).unwrap();
        std::fs::write(unified.join("stray.txt"), "").unwrap();

        let found = discover_sessions(tmp.path());
        assert_eq!(found.len(), 2);
        assert_eq!(found[0].0.session_id, "older"); // sorted by start_time
        assert_eq!(found[1].0.session_id, "newer");

        let newer = &found[1].0;
        assert_eq!(newer.cwd.as_deref(), Some("/home/me/proj-a"));
        assert_eq!(newer.title.as_deref(), Some("Some title"));
        assert!(newer.parent_session_id.is_none());
        assert_eq!(newer.child_sessions, vec!["kid-1".to_string()]);
        assert_eq!(newer.start_time_ms, Some(1790600400000)); // 2026-09-28T13:00Z

        let older = &found[0].0;
        assert_eq!(older.parent_session_id.as_deref(), Some("some-parent"));
        assert!(older.title.is_none());
    }
}
