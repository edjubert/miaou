//! Active session detection from Vibe's lock files.
//!
//! Vibe writes `<session-id>.lock` files in `$VIBE_HOME/logs/session/active/`
//! for every running session. The lock's mtime tracks liveness.

use serde::Serialize;
use std::path::Path;
use std::time::SystemTime;

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ActiveSession {
    pub id: String,
    /// Milliseconds since the lock was last touched.
    pub age_ms: u64,
}

/// List active sessions, most recently touched first.
pub fn active_sessions(vibe_home: &Path) -> Vec<ActiveSession> {
    let dir = vibe_home.join("logs").join("session").join("active");
    let mut out = Vec::new();
    let Ok(entries) = std::fs::read_dir(&dir) else {
        return out;
    };
    for entry in entries.flatten() {
        let file_name = entry.file_name();
        let Some(id) = file_name.to_str().and_then(|n| n.strip_suffix(".lock")) else {
            continue;
        };
        let Ok(modified) = entry.metadata().and_then(|m| m.modified()) else {
            continue;
        };
        let age = SystemTime::now()
            .duration_since(modified)
            .unwrap_or_default()
            .as_millis() as u64;
        out.push(ActiveSession {
            id: id.to_owned(),
            age_ms: age,
        });
    }
    out.sort_by_key(|s| s.age_ms);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_locks_and_ignores_others() {
        let tmp = tempfile::tempdir().unwrap();
        let active = tmp.path().join("logs").join("session").join("active");
        std::fs::create_dir_all(&active).unwrap();
        std::fs::write(active.join("aaa.lock"), "").unwrap();
        std::fs::write(active.join("bbb.lock.json"), "{}").unwrap();
        std::fs::write(active.join("stray.txt"), "").unwrap();

        let found = active_sessions(tmp.path());
        assert_eq!(found.len(), 1);
        assert_eq!(found[0].id, "aaa");
        assert!(found[0].age_ms < 5_000);
    }

    #[test]
    fn missing_active_dir_is_empty() {
        let tmp = tempfile::tempdir().unwrap();
        assert!(active_sessions(tmp.path()).is_empty());
    }
}
