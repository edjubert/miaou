//! Public CLI contract: all consumers agree on task activity across ACP turns.

#![cfg(unix)]

use std::os::fd::AsRawFd;
use std::path::Path;

fn output(home: &Path, command: &str) -> serde_json::Value {
    let result = std::process::Command::new(env!("CARGO_BIN_EXE_miaou"))
        .args(["--vibe-home", home.to_str().unwrap(), command, "--json"])
        .env("MIAOU_ARCHIVE_PATH", home.join("archive.jsonl"))
        .env("XDG_CONFIG_HOME", home.join("config"))
        .output()
        .unwrap();
    assert!(
        result.status.success(),
        "{}",
        String::from_utf8_lossy(&result.stderr)
    );
    serde_json::from_slice(&result.stdout).unwrap()
}

#[test]
fn status_dashboard_and_session_flags_agree_on_turn_boundaries() {
    let temp = tempfile::tempdir().unwrap();
    let home = temp.path();
    let dir = home.join("logs/session/unified/acp");
    let active = home.join("logs/session/active");
    std::fs::create_dir_all(dir.join("journal")).unwrap();
    std::fs::create_dir_all(&active).unwrap();
    let lease = std::fs::File::create(active.join("acp.lock")).unwrap();
    assert_eq!(
        unsafe { libc::flock(lease.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) },
        0
    );
    let now = chrono::Utc::now();
    std::fs::write(
        dir.join("meta.json"),
        serde_json::json!({
            "session_id": "acp", "title": "A task", "title_source": "manual",
            "start_time": now.to_rfc3339(), "bumped_at": now.to_rfc3339(),
            "end_time": now.to_rfc3339(),
        })
        .to_string(),
    )
    .unwrap();
    // Give dashboard/sessions a real usage event without involving local data.
    let usage = serde_json::json!({
        "sequence": 1, "type": "action_result", "payload": {
            "result": {"type": "completion_succeeded", "result": {
                "finish_reason": "stop",
                "usage": {"input_tokens": 10, "output_tokens": 5, "total_tokens": 15}
            }}
        }
    });
    std::fs::write(
        dir.join("journal/0000000000000001.jsonl"),
        usage.to_string() + "\n",
    )
    .unwrap();
    for (sequence, state, running) in [
        (2, "in_progress", true),
        (3, "completed", false),
        (4, "in_progress", true),
        (5, "failed", false),
        (6, "in_progress", true),
        (7, "interrupted", false),
    ] {
        use std::io::Write;
        let mut journal = std::fs::OpenOptions::new()
            .append(true)
            .open(dir.join("journal/0000000000000001.jsonl"))
            .unwrap();
        writeln!(
            journal,
            "{}",
            serde_json::json!({
                "sequence": sequence, "type": "projection_delta", "payload": {
                    "delta": [{"op": "set_envelope", "state": {
                        "latestTurn": {"status": state}
                    }}]
                }
            })
        )
        .unwrap();
        let status = output(home, "status");
        assert_eq!(
            status["active"].as_array().unwrap().len(),
            usize::from(running)
        );
        assert!(status.get("totals").is_none());
        if running {
            assert_eq!(status["active"][0]["title"], "A task");
            assert_eq!(status["active"][0]["title_source"], "manual");
        }
        let dashboard = output(home, "dashboard");
        assert_eq!(
            dashboard["active"].as_array().unwrap().len(),
            usize::from(running)
        );
        assert_eq!(dashboard["sessions"][0]["active"], running);
        let sessions = output(home, "sessions");
        assert_eq!(sessions[0]["active"], running);
    }
    assert_eq!(unsafe { libc::flock(lease.as_raw_fd(), libc::LOCK_UN) }, 0);
    assert!(output(home, "status")["active"]
        .as_array()
        .unwrap()
        .is_empty());
}
