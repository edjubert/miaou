//! End-to-end tests over a synthetic `$VIBE_HOME`: discover sessions, parse
//! journals, aggregate, and estimate cost against a configured price table.

use std::path::Path;
use vibe_god_cli::aggregate::{aggregate_by_project, aggregate_by_session};
use vibe_god_cli::prices::VibeConfig;
use vibe_god_cli::{collect_all, Totals};

fn record(sequence: u64, r#type: &str, body: serde_json::Value) -> String {
    serde_json::json!({"type": r#type, "sequence": sequence, "payload": body}).to_string()
}

fn completion(sequence: u64, input: u64, output: u64, cached: u64) -> String {
    record(
        sequence,
        "action_result",
        serde_json::json!({
            "result": {
                "result": {
                    "finish_reason": "stop",
                    "usage": {
                        "input_tokens": input, "output_tokens": output,
                        "cached_input_tokens": cached,
                        "total_tokens": input + output
                    }
                },
                "type": "completion_succeeded"
            },
            "state": "succeeded"
        }),
    )
}

fn anchor(sequence: u64, ms: i64) -> String {
    record(
        sequence,
        "core_input",
        serde_json::json!({"input": {"determinism": {"time_unix_ms": ms}}}),
    )
}

fn write_session(
    unified: &Path,
    id: &str,
    cwd: &str,
    start_iso: &str,
    parent: Option<&str>,
    journal: &str,
) {
    let dir = unified.join(id);
    std::fs::create_dir_all(dir.join("journal")).unwrap();
    let meta = serde_json::json!({
        "session_id": id,
        "environment": {"working_directory": cwd},
        "start_time": start_iso,
        "parent_session_id": parent,
        "child_sessions": [],
    });
    std::fs::write(dir.join("meta.json"), meta.to_string()).unwrap();
    std::fs::write(dir.join("journal").join("0000000000000001.jsonl"), journal).unwrap();
}

fn synthetic_home() -> tempfile::TempDir {
    let tmp = tempfile::tempdir().unwrap();
    let unified = tmp.path().join("logs").join("session").join("unified");
    std::fs::create_dir_all(&unified).unwrap();

    write_session(
        &unified,
        "session-aaaa",
        "/home/me/alpha",
        "2026-09-28T10:00:00+00:00",
        None,
        &format!(
            "{}\n{}\n{}\n{}\n",
            anchor(1, 1790599200000),
            completion(2, 1000, 100, 500),
            anchor(3, 1790602800000),
            completion(4, 2000, 200, 1000),
        ),
    );
    write_session(
        &unified,
        "session-bbbb",
        "/home/me/beta",
        "2026-09-28T11:00:00+00:00",
        Some("session-aaaa"),
        &format!("{}\n{}\n", anchor(1, 1790602800000), completion(2, 3000, 300, 0)),
    );
    // Decoy: a directory without meta.json must be ignored.
    std::fs::create_dir_all(unified.join("decoy").join("journal")).unwrap();

    tmp
}

#[test]
fn end_to_end_collects_and_aggregates() {
    let home = synthetic_home();
    let sessions = collect_all(home.path());
    assert_eq!(sessions.len(), 2);

    let all: Vec<&vibe_god_cli::SessionUsage> = sessions.iter().collect();
    let mut grand = Totals::default();
    for s in &all {
        grand.add(&s.totals());
    }
    assert_eq!(grand.requests, 3);
    assert_eq!(grand.input_tokens, 6000);
    assert_eq!(grand.output_tokens, 600);
    assert_eq!(grand.cached_input_tokens, 1500);
    assert_eq!(grand.total_tokens, 6600);

    // Timestamps interpolated from the nearest anchors.
    let a = sessions.iter().find(|s| s.meta.session_id == "session-aaaa").unwrap();
    assert_eq!(a.events[0].timestamp_ms, 1790599200000);
    assert_eq!(a.events[1].timestamp_ms, 1790602800000);

    // Projects.
    let projects = aggregate_by_project(&sessions);
    let find = |k: &str| projects.iter().find(|r| r.key == k).unwrap();
    assert_eq!(find("alpha").totals.requests, 2);
    assert_eq!(find("beta").totals.requests, 1);

    // Sessions: subagent flagged, newest first.
    let rows = aggregate_by_session(&sessions);
    assert_eq!(rows.len(), 2);
    assert_eq!(rows[0].session_id, "session-bbbb"); // started later
    assert!(rows[0].subagent);
    assert!(!rows[1].subagent);
}

#[test]
fn cost_estimation_uses_configured_prices() {
    let home = synthetic_home();
    let sessions = collect_all(home.path());

    let mut grand = Totals::default();
    for s in &sessions {
        grand.add(&s.totals());
    }
    assert!(grand.cost_usd.is_none());

    std::fs::write(
        home.path().join("config.toml"),
        r#"
active_model = "glm-5-3"

[[models]]
name = "zai-glm-5-3"
provider = "mistral"
alias = "glm-5-3"
input_price = 2.0
output_price = 6.0
cached_input_price = 0.2
"#,
    )
    .unwrap();

    let config = VibeConfig::load(home.path());
    let price = config.resolve(None).expect("active model resolves");
    let cost = price
        .cost_usd(grand.input_tokens, grand.output_tokens, grand.cached_input_tokens)
        .unwrap();
    // uncached 4500 * 2.0 + cached 1500 * 0.2 + 600 * 6.0, per million tokens.
    assert!((cost - 0.0129).abs() < 1e-9, "{cost}");
}

#[test]
fn empty_home_yields_nothing() {
    let tmp = tempfile::tempdir().unwrap();
    assert!(collect_all(tmp.path()).is_empty());
}
