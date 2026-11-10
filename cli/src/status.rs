//! Active session detection from Vibe's lock files.
//!
//! Vibe writes `<session-id>.lock` files in `$VIBE_HOME/logs/session/active/`
//! and holds an exclusive OS lock while the session is open. The file can
//! survive a crash or be touched by maintenance, so its mtime is not liveness.

use serde::Serialize;
use std::io::{BufRead, BufReader};
use std::path::Path;
use std::time::SystemTime;

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ActiveSession {
    pub id: String,
    /// Milliseconds since the lock was last touched.
    pub age_ms: u64,
}

/// Compatibility fallback for old stores without an explicit turn state.
/// Modern stores use the public projection's latestTurn instead.
pub const ACTIVE_FRESHNESS_MS: u64 = 15 * 60 * 1000;

/// True when the last metadata save (`bumped_at`) is within the freshness
/// window. Unknown `bumped_at` fails open: a held lease with no readable
/// metadata still counts as active.
pub fn session_is_active(bumped_at_ms: Option<u64>, now_ms: u64) -> bool {
    match bumped_at_ms {
        Some(b) => now_ms.saturating_sub(b) <= ACTIVE_FRESHNESS_MS,
        None => true,
    }
}

/// The ACP server holds user sessions even between prompts. Keep its leases:
/// live_sessions distinguishes a running turn from an idle server.
const EXCLUDED_LEASE_HOLDERS: [&str; 1] = ["vibe-app-server"];

/// Process id recorded in the `<id>.lock.json` diagnostic beside a lease file.
fn lease_holder_pid(lock_path: &Path) -> Option<u64> {
    let diagnostic = lock_path.with_extension("lock.json");
    let raw = std::fs::read_to_string(diagnostic).ok()?;
    let value: serde_json::Value = serde_json::from_str(&raw).ok()?;
    value.get("process_id").and_then(|p| p.as_u64())
}

/// Full command line of `pid`, via `ps` (None when the pid is gone). The
/// Vibe tools are Python scripts, so their executable name (`comm`) is the
/// interpreter; the tool name only appears in the command line.
fn process_command(pid: u64) -> Option<String> {
    let output = std::process::Command::new("ps")
        .args(["-p", &pid.to_string(), "-o", "args="])
        .output()
        .ok()?;
    let command = String::from_utf8_lossy(&output.stdout).trim().to_string();
    (!command.is_empty()).then_some(command)
}

/// True when one of the command line's arguments is an excluded holder name,
/// matched as a path component so "not-vibe-acp" does not match.
fn is_excluded_holder(command: &str) -> bool {
    EXCLUDED_LEASE_HOLDERS.iter().any(|excluded| {
        command
            .split_whitespace()
            .any(|arg| arg.split('/').any(|component| component == *excluded))
    })
}

/// True when the lease's recorded holder is an excluded process. A missing or
/// unreadable diagnostic fails open: not excluded.
fn lease_holder_excluded(lock_path: &Path) -> bool {
    lease_holder_pid(lock_path)
        .and_then(process_command)
        .is_some_and(|command| is_excluded_holder(&command))
}

/// A held lease is necessary, but does not prove a task is running.
/// Explicit turn state takes priority over metadata freshness, including for
/// long-running turns and for completed turns whose metadata was just saved.
pub fn live_sessions(vibe_home: &Path, now_ms: u64) -> Vec<ActiveSession> {
    active_sessions(vibe_home)
        .into_iter()
        .filter(|session| {
            let dir = vibe_home.join("logs/session/unified").join(&session.id);
            turn_is_running(&dir).unwrap_or_else(|| {
                let bumped = read_json(&dir.join("meta.json"))
                    .and_then(|m| {
                        m.get("bumped_at")
                            .and_then(|v| v.as_str())
                            .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
                    })
                    .map(|dt| dt.timestamp_millis().max(0) as u64);
                session_is_active(bumped, now_ms)
            })
        })
        .collect()
}

fn read_json(path: &Path) -> Option<serde_json::Value> {
    serde_json::from_reader(std::fs::File::open(path).ok()?).ok()
}

/// Read the committed projection and then its journal tail. Generations are
/// published through CURRENT; picking the largest directory can observe an
/// unpublished generation. Journal projections are newer than the checkpoint
/// while a prompt is running, so reading only the checkpoint misses resumes.
fn turn_is_running(session_dir: &Path) -> Option<bool> {
    let pointer = read_json(&session_dir.join("CURRENT"));
    let snapshot_sequence = pointer
        .as_ref()
        .and_then(|p| p.get("snapshot_sequence"))
        .and_then(|s| s.as_u64())
        .unwrap_or(0);
    let snapshot = pointer
        .as_ref()
        .and_then(|p| p.get("generation"))
        .and_then(|g| g.as_str())
        .filter(|g| {
            !g.is_empty() && *g != "." && *g != ".." && !g.contains('/') && !g.contains('\\')
        })
        .and_then(|generation| {
            read_json(
                &session_dir
                    .join("generations")
                    .join(generation)
                    .join("projection-state.json"),
            )
        });
    let baseline = snapshot
        .as_ref()
        .and_then(|p| p.get("snapshot"))
        .and_then(projection_is_running);

    let Ok(entries) = std::fs::read_dir(session_dir.join("journal")) else {
        return baseline;
    };
    let mut files: Vec<_> = entries
        .flatten()
        .filter_map(|entry| {
            let path = entry.path();
            let first_sequence = path
                .file_name()?
                .to_str()?
                .strip_suffix(".jsonl")?
                .parse::<u64>()
                .ok()?;
            // Publishing a generation starts a new segment at snapshot + 1.
            // No old transcript needs to be read on the two-second activity poll.
            (first_sequence > snapshot_sequence).then_some((first_sequence, path))
        })
        .collect();
    files.sort_by_key(|(sequence, _)| *sequence);
    for (_, path) in files.into_iter().rev() {
        let Ok(file) = std::fs::File::open(path) else {
            continue;
        };
        let mut latest = None;
        for line in BufReader::new(file).lines().map_while(Result::ok) {
            // A writer can leave a partial final JSONL record while appending.
            let Ok(record) = serde_json::from_str::<serde_json::Value>(&line) else {
                continue;
            };
            let Some(sequence) = record.get("sequence").and_then(|s| s.as_u64()) else {
                continue;
            };
            if sequence <= snapshot_sequence {
                continue;
            }
            let state = match record.get("type").and_then(|t| t.as_str()) {
                Some("projection_advanced") => record.pointer("/payload/snapshot"),
                Some("projection_delta") => record
                    .pointer("/payload/delta")
                    .and_then(|d| d.as_array())
                    .and_then(|ops| {
                        ops.iter().rev().find(|op| {
                            op.get("op").and_then(|v| v.as_str()) == Some("set_envelope")
                        })
                    })
                    .and_then(|op| op.get("state")),
                _ => None,
            };
            if let Some(state) = state {
                if latest
                    .as_ref()
                    .is_none_or(|(previous, _)| sequence > *previous)
                {
                    latest = Some((sequence, projection_is_running(state)));
                }
            }
        }
        if let Some((_, running)) = latest {
            return running;
        }
    }
    baseline
}

fn projection_is_running(state: &serde_json::Value) -> Option<bool> {
    let turn = state.get("latestTurn")?;
    if turn.is_null() {
        return Some(false);
    }
    match turn.get("status").and_then(|s| s.as_str())? {
        "in_progress" => Some(true),
        "completed" | "failed" | "interrupted" => Some(false),
        _ => None,
    }
}

/// List sessions whose OS lock is still held, most recently touched first.
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
        // This lease belongs to Vibe's background cleanup, not a session.
        if id == "process-output-cleanup" {
            continue;
        }
        // Leases held by the app server are its own API/ACP sessions.
        if lease_holder_excluded(&entry.path()) {
            continue;
        }
        let Ok(file) = std::fs::File::open(entry.path()) else {
            continue;
        };
        let Ok(metadata) = file.metadata() else {
            continue;
        };
        if !metadata.is_file() || !lock_is_held(&file) {
            continue;
        }
        let Ok(modified) = metadata.modified() else {
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

#[cfg(unix)]
fn lock_is_held(file: &std::fs::File) -> bool {
    use std::os::fd::AsRawFd;

    // Probe Vibe's flock without waiting or modifying the file. A shared lock
    // conflicts with its exclusive lease; success means the file is orphaned.
    let result = unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_SH | libc::LOCK_NB) };
    if result == 0 {
        unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_UN) };
        false
    } else {
        std::io::Error::last_os_error().raw_os_error() == Some(libc::EWOULDBLOCK)
    }
}

#[cfg(not(unix))]
fn lock_is_held(_file: &std::fs::File) -> bool {
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg(unix)]
    struct TestLease(std::fs::File);

    #[cfg(unix)]
    impl std::ops::Deref for TestLease {
        type Target = std::fs::File;
        fn deref(&self) -> &Self::Target {
            &self.0
        }
    }

    #[cfg(unix)]
    impl Drop for TestLease {
        fn drop(&mut self) {
            use std::os::fd::AsRawFd;
            // Like Vibe's lease release, unlock explicitly. Another parallel
            // test can be between fork and exec and briefly inherit this fd;
            // closing our copy alone would then leave its lock held.
            assert_eq!(unsafe { libc::flock(self.0.as_raw_fd(), libc::LOCK_UN) }, 0);
        }
    }

    #[cfg(unix)]
    fn hold_lock(path: &Path) -> TestLease {
        use std::os::fd::AsRawFd;

        let file = std::fs::File::create(path).unwrap();
        assert_eq!(
            unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) },
            0
        );
        TestLease(file)
    }

    #[cfg(unix)]
    #[test]
    fn detects_held_locks_and_ignores_orphans_and_maintenance() {
        let tmp = tempfile::tempdir().unwrap();
        let active = tmp.path().join("logs").join("session").join("active");
        std::fs::create_dir_all(&active).unwrap();
        let _held = hold_lock(&active.join("aaa.lock"));
        let _maintenance = hold_lock(&active.join("process-output-cleanup.lock"));
        std::fs::write(active.join("orphan.lock"), "").unwrap();
        // Even a live PID is insufficient: maintenance may have released its
        // session lease while keeping the process running.
        std::fs::write(
            active.join("orphan.lock.json"),
            format!(r#"{{"process_id":{}}}"#, std::process::id()),
        )
        .unwrap();
        std::fs::write(active.join("bbb.lock.json"), "{}").unwrap();
        std::fs::write(active.join("stray.txt"), "").unwrap();
        std::fs::create_dir(active.join("directory.lock")).unwrap();

        let found = active_sessions(tmp.path());
        assert_eq!(found.len(), 1);
        assert_eq!(found[0].id, "aaa");
        assert!(found[0].age_ms < 5_000);
    }

    #[cfg(unix)]
    #[test]
    fn held_lock_stays_active_without_a_recent_mtime() {
        let tmp = tempfile::tempdir().unwrap();
        let active = tmp.path().join("logs/session/active");
        std::fs::create_dir_all(&active).unwrap();
        let held = hold_lock(&active.join("old.lock"));
        let old = SystemTime::now() - std::time::Duration::from_secs(600);
        held.set_times(std::fs::FileTimes::new().set_modified(old))
            .unwrap();

        let found = active_sessions(tmp.path());
        assert_eq!(found.len(), 1);
        assert_eq!(found[0].id, "old");
        assert!(found[0].age_ms >= 600_000);

        drop(held);
        assert!(active_sessions(tmp.path()).is_empty());
    }

    #[cfg(unix)]
    #[test]
    fn abrupt_process_exit_leaves_no_active_session() {
        use std::io::{BufRead, BufReader};
        use std::process::{Command, Stdio};

        let tmp = tempfile::tempdir().unwrap();
        let active = tmp.path().join("logs/session/active");
        std::fs::create_dir_all(&active).unwrap();
        let path = active.join("child.lock");
        let mut child = Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "status::tests::lock_holder", "--nocapture"])
            .env("MIAOU_TEST_LOCK_PATH", &path)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()
            .unwrap();
        let mut output = BufReader::new(child.stdout.take().unwrap());
        loop {
            let mut line = String::new();
            assert!(output.read_line(&mut line).unwrap() > 0);
            if line.contains("MIAOU_LOCK_READY") {
                break;
            }
        }
        let found = active_sessions(tmp.path());
        child.kill().unwrap();
        child.wait().unwrap();

        assert_eq!(found.len(), 1);
        assert_eq!(found[0].id, "child");
        assert!(path.exists(), "The orphaned lock file must remain.");
        assert!(active_sessions(tmp.path()).is_empty());
    }

    #[cfg(unix)]
    #[test]
    fn lock_holder() {
        use std::io::{Read, Write};

        let Some(path) = std::env::var_os("MIAOU_TEST_LOCK_PATH") else {
            return;
        };
        let _held = hold_lock(Path::new(&path));
        println!("MIAOU_LOCK_READY");
        std::io::stdout().flush().unwrap();
        let _ = std::io::stdin().read(&mut [0]);
    }

    #[test]
    fn missing_active_dir_is_empty() {
        let tmp = tempfile::tempdir().unwrap();
        assert!(active_sessions(tmp.path()).is_empty());
    }

    #[test]
    fn lease_holder_pid_reads_diagnostic() {
        let tmp = tempfile::tempdir().unwrap();
        let lock = tmp.path().join("abc.lock");
        std::fs::write(&lock, "").unwrap();
        assert_eq!(lease_holder_pid(&lock), None);
        std::fs::write(lock.with_extension("lock.json"), r#"{"process_id": 4242}"#).unwrap();
        assert_eq!(lease_holder_pid(&lock), Some(4242));
        // Torn read: not a pid.
        std::fs::write(lock.with_extension("lock.json"), r#"{"process_id": "x"}"#).unwrap();
        assert_eq!(lease_holder_pid(&lock), None);
    }

    #[test]
    fn excluded_holder_names() {
        assert!(is_excluded_holder("vibe-app-server"));
        assert!(is_excluded_holder("/usr/local/bin/vibe-app-server"));
        assert!(!is_excluded_holder("vibe-acp"));
        assert!(!is_excluded_holder("/Users/x/.local/bin/vibe-acp"));
        // Script-based tools show the interpreter as executable; the tool
        // name is matched in the command line arguments.
        assert!(!is_excluded_holder(
            "/opt/Python.app/Contents/MacOS/Python /Users/x/.local/bin/vibe-acp"
        ));
        assert!(is_excluded_holder(
            "/opt/Python /Users/x/.local/bin/vibe-app-server --port 8080"
        ));
        // The user-facing CLI is not a server: never excluded.
        assert!(!is_excluded_holder("vibe"));
        assert!(!is_excluded_holder("/opt/Python /Users/x/.local/bin/vibe"));
        assert!(!is_excluded_holder("not-vibe-acp"));
        assert!(!is_excluded_holder("Python"));
    }

    #[test]
    fn freshness_window_filters_stale_but_keeps_unknown() {
        let now = 1_000_000_000_000;
        assert!(session_is_active(Some(now), now));
        assert!(session_is_active(Some(now - ACTIVE_FRESHNESS_MS), now));
        assert!(!session_is_active(Some(now - ACTIVE_FRESHNESS_MS - 1), now));
        // No metadata: fail open, the held lease is the only signal left.
        assert!(session_is_active(None, now));
    }

    fn write_projection(dir: &Path, sequence: u64, status: Option<&str>) {
        let generation = format!("{sequence:016}");
        let path = dir.join("generations").join(&generation);
        std::fs::create_dir_all(&path).unwrap();
        std::fs::write(
            dir.join("CURRENT"),
            serde_json::json!({
                "generation": generation, "snapshot_sequence": sequence,
            })
            .to_string(),
        )
        .unwrap();
        std::fs::write(
            path.join("projection-state.json"),
            serde_json::json!({
                "snapshot": {"latestTurn": status.map(|s| serde_json::json!({"status": s}))},
            })
            .to_string(),
        )
        .unwrap();
    }

    fn projection_record(sequence: u64, status: &str) -> String {
        serde_json::json!({
            "sequence": sequence, "type": "projection_delta",
            "payload": {"delta": [{"op": "set_envelope", "state": {
                "latestTurn": {"status": status}
            }}]},
        })
        .to_string()
            + "\n"
    }

    #[cfg(unix)]
    #[test]
    fn explicit_turn_state_overrides_freshness_and_survives_resume() {
        use std::io::Write;
        let tmp = tempfile::tempdir().unwrap();
        let home = tmp.path();
        let active = home.join("logs/session/active");
        let dir = home.join("logs/session/unified/acp");
        std::fs::create_dir_all(&active).unwrap();
        std::fs::create_dir_all(dir.join("journal")).unwrap();
        let held = hold_lock(&active.join("acp.lock"));
        let now = 1_700_000_000_000u64;
        let fresh = chrono::DateTime::from_timestamp_millis(now as i64).unwrap();
        std::fs::write(
            dir.join("meta.json"),
            serde_json::json!({
                "session_id": "acp", "bumped_at": fresh.to_rfc3339(),
                "end_time": fresh.to_rfc3339(),
            })
            .to_string(),
        )
        .unwrap();

        for status in [Some("completed"), Some("failed"), Some("interrupted"), None] {
            write_projection(&dir, 10, status);
            assert!(live_sessions(home, now).is_empty(), "{status:?}");
        }
        // A task cannot disappear just because it runs longer than 15 minutes.
        write_projection(&dir, 10, Some("in_progress"));
        assert_eq!(live_sessions(home, now + ACTIVE_FRESHNESS_MS + 1).len(), 1);

        write_projection(&dir, 10, Some("completed"));
        // Old journal state cannot resurrect a newer committed terminal state.
        std::fs::write(
            dir.join("journal/0000000000000001.jsonl"),
            projection_record(9, "in_progress"),
        )
        .unwrap();
        assert!(live_sessions(home, now).is_empty());

        let mut journal =
            std::fs::File::create(dir.join("journal/0000000000000011.jsonl")).unwrap();
        journal
            .write_all(projection_record(11, "in_progress").as_bytes())
            .unwrap();
        assert_eq!(live_sessions(home, now).len(), 1);
        // Tool completions and malformed concurrent writes do not end a turn.
        journal.write_all(b"{\"sequence\":12,\"type\":\"action_result\",\"payload\":{\"result\":{\"type\":\"completion_succeeded\",\"result\":{\"finish_reason\":\"stop\"}}}}\n{\"sequence\":13,").unwrap();
        assert_eq!(live_sessions(home, now).len(), 1);
        journal.write_all(b"\"type\":\"ignored\"}\n").unwrap();
        journal
            .write_all(projection_record(14, "completed").as_bytes())
            .unwrap();
        assert!(live_sessions(home, now).is_empty());
        // Resume after another idle boundary, without releasing the ACP lease.
        journal
            .write_all(projection_record(15, "in_progress").as_bytes())
            .unwrap();
        assert_eq!(live_sessions(home, now).len(), 1);
        drop(held);
        assert!(live_sessions(home, now).is_empty());
    }

    #[test]
    fn projection_reader_handles_empty_tails_rotation_and_legacy_records() {
        let tmp = tempfile::tempdir().unwrap();
        let dir = tmp.path();
        std::fs::create_dir_all(dir.join("journal")).unwrap();
        write_projection(dir, 10, Some("in_progress"));
        std::fs::write(dir.join("journal/0000000000000011.jsonl"), "").unwrap();
        assert_eq!(turn_is_running(dir), Some(true));
        std::fs::write(
            dir.join("journal/0000000000000011.jsonl"),
            projection_record(11, "interrupted"),
        )
        .unwrap();
        std::fs::write(
            dir.join("journal/0000000000000012.jsonl"),
            "{\"sequence\":12,\"type\":\"action_result\"}\n",
        )
        .unwrap();
        assert_eq!(turn_is_running(dir), Some(false));
        // Before projection deltas, Vibe emitted whole public snapshots.
        std::fs::write(
            dir.join("journal/0000000000000012.jsonl"),
            serde_json::json!({"sequence":12,"type":"projection_advanced",
                "payload":{"snapshot":{"latestTurn":{"status":"in_progress"}}}
            })
            .to_string(),
        )
        .unwrap();
        assert_eq!(turn_is_running(dir), Some(true));
        // A newer unknown format must not reuse an older known state.
        std::fs::write(
            dir.join("journal/0000000000000013.jsonl"),
            projection_record(13, "future_state"),
        )
        .unwrap();
        assert_eq!(turn_is_running(dir), None);
    }

    #[test]
    fn only_the_generation_published_by_current_defines_the_baseline() {
        let tmp = tempfile::tempdir().unwrap();
        let dir = tmp.path();
        write_projection(dir, 10, Some("completed"));
        let pending = dir.join("generations/0000000000000099");
        std::fs::create_dir_all(&pending).unwrap();
        std::fs::write(
            pending.join("projection-state.json"),
            r#"{"snapshot":{"latestTurn":{"status":"in_progress"}}}"#,
        )
        .unwrap();
        assert_eq!(turn_is_running(dir), Some(false));
        write_projection(dir, 99, Some("in_progress"));
        assert_eq!(turn_is_running(dir), Some(true));
    }

    #[cfg(unix)]
    #[test]
    fn legacy_stores_keep_freshness_fallback() {
        let tmp = tempfile::tempdir().unwrap();
        let home = tmp.path();
        let active = home.join("logs/session/active");
        let dir = home.join("logs/session/unified/legacy");
        std::fs::create_dir_all(&active).unwrap();
        std::fs::create_dir_all(&dir).unwrap();
        let _held = hold_lock(&active.join("legacy.lock"));
        let now = 1_700_000_000_000u64;
        let fresh = chrono::DateTime::from_timestamp_millis(now as i64).unwrap();
        std::fs::write(
            dir.join("meta.json"),
            serde_json::json!({
                "bumped_at": fresh.to_rfc3339(),
            })
            .to_string(),
        )
        .unwrap();
        assert_eq!(live_sessions(home, now).len(), 1);
        assert!(live_sessions(home, now + ACTIVE_FRESHNESS_MS + 1).is_empty());
        std::fs::write(dir.join("CURRENT"), "{").unwrap();
        assert_eq!(live_sessions(home, now).len(), 1);
    }
    #[cfg(unix)]
    fn write_meta(home: &Path, id: &str, bumped_at_ms: Option<u64>) {
        let dir = home.join("logs/session/unified").join(id);
        std::fs::create_dir_all(&dir).unwrap();
        let bumped = bumped_at_ms
            .map(|ms| {
                let dt = chrono::DateTime::from_timestamp_millis(ms as i64).unwrap();
                format!(r#","bumped_at":"{}""#, dt.to_rfc3339())
            })
            .unwrap_or_default();
        std::fs::write(
            dir.join("meta.json"),
            format!(r#"{{"session_id":"{id}"{bumped}}}"#),
        )
        .unwrap();
    }

    /// Spawn a child that holds `path`'s lock, with a fake argv[0] so the
    /// holder-name exclusion can be exercised end to end.
    #[cfg(unix)]
    fn spawn_lock_holder(path: &Path, argv0: &str) -> std::process::Child {
        use std::io::{BufRead, BufReader};
        use std::os::unix::process::CommandExt;

        let mut cmd = std::process::Command::new(std::env::current_exe().unwrap());
        cmd.args(["--exact", "status::tests::lock_holder", "--nocapture"])
            .env("MIAOU_TEST_LOCK_PATH", path)
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .arg0(argv0);
        let mut child = cmd.spawn().unwrap();
        let mut output = BufReader::new(child.stdout.take().unwrap());
        loop {
            let mut line = String::new();
            assert!(output.read_line(&mut line).unwrap() > 0);
            if line.contains("MIAOU_LOCK_READY") {
                break;
            }
        }
        child
    }

    /// End-to-end liveness: held lease + fresh metadata is active, stale
    /// metadata is not, a missing metadata fails open, an orphaned lock is
    /// not, the maintenance lease and app-server leases are excluded, and
    /// an ACP-held lease (user session driven through ACP) IS active.
    #[cfg(unix)]
    #[test]
    fn live_sessions_combines_lease_freshness_and_holder() {
        let tmp = tempfile::tempdir().unwrap();
        let home = tmp.path();
        let active = home.join("logs/session/active");
        std::fs::create_dir_all(&active).unwrap();
        let now = 1_700_000_000_000u64;
        let fresh = now - 60_000;
        let stale = now - ACTIVE_FRESHNESS_MS - 1;

        // Held lease + fresh metadata: active.
        let _fresh = hold_lock(&active.join("fresh.lock"));
        write_meta(home, "fresh", Some(fresh));
        // Held lease + stale metadata: not active.
        let _stale = hold_lock(&active.join("stale.lock"));
        write_meta(home, "stale", Some(stale));
        // Held lease + no metadata: fail open, active.
        let _nometa = hold_lock(&active.join("nometa.lock"));
        // Orphaned lock + fresh metadata: not active.
        std::fs::write(active.join("orphan.lock"), "").unwrap();
        write_meta(home, "orphan", Some(fresh));
        // Maintenance lease: never active.
        let _cleanup = hold_lock(&active.join("process-output-cleanup.lock"));
        // App-server-held lease: excluded even with fresh metadata.
        let appserver_lock = active.join("appserver.lock");
        let mut appserver = spawn_lock_holder(&appserver_lock, "vibe-app-server");
        std::fs::write(
            active.join("appserver.lock.json"),
            format!(r#"{{"process_id":{}}}"#, appserver.id()),
        )
        .unwrap();
        write_meta(home, "appserver", Some(fresh));
        // ACP-held lease: a user session driven through ACP, must stay active.
        let acp_lock = active.join("acp.lock");
        let mut acp = spawn_lock_holder(&acp_lock, "vibe-acp");
        std::fs::write(
            active.join("acp.lock.json"),
            format!(r#"{{"process_id":{}}}"#, acp.id()),
        )
        .unwrap();
        write_meta(home, "acp", Some(fresh));

        let live = live_sessions(home, now);
        let mut ids: Vec<&str> = live.iter().map(|a| a.id.as_str()).collect();
        ids.sort_unstable();
        assert_eq!(ids, vec!["acp", "fresh", "nometa"]);

        // Once the ACP child releases its lease, the session goes inactive.
        acp.kill().unwrap();
        acp.wait().unwrap();
        appserver.kill().unwrap();
        appserver.wait().unwrap();
        let live = live_sessions(home, now);
        let mut ids: Vec<&str> = live.iter().map(|a| a.id.as_str()).collect();
        ids.sort_unstable();
        assert_eq!(ids, vec!["fresh", "nometa"]);
    }
}
