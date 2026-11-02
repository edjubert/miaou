//! Active session detection from Vibe's lock files.
//!
//! Vibe writes `<session-id>.lock` files in `$VIBE_HOME/logs/session/active/`
//! and holds an exclusive OS lock while the session is open. The file can
//! survive a crash or be touched by maintenance, so its mtime is not liveness.

use serde::Serialize;
use std::path::Path;
use std::time::SystemTime;

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ActiveSession {
    pub id: String,
    /// Milliseconds since the lock was last touched.
    pub age_ms: u64,
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
    fn hold_lock(path: &Path) -> std::fs::File {
        use std::os::fd::AsRawFd;

        let file = std::fs::File::create(path).unwrap();
        assert_eq!(
            unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) },
            0
        );
        file
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
}
