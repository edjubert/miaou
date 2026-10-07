//! Journal parsing: extract usage events and interpolate their timestamps.
//!
//! Journal records are JSONL lines of the shape:
//!
//! ```json
//! {
//!   "payload": {
//!     "action_id": "...",
//!     "result": {
//!       "action_id": "...",
//!       "result": { "finish_reason": "...", "parts": [...],
//!                   "usage": { "input_tokens": 0, "output_tokens": 0,
//!                              "cached_input_tokens": 0, "total_tokens": 0 } },
//!       "type": "completion_succeeded"
//!     },
//!     "state": "succeeded"
//!   },
//!   "sequence": 9,
//!   "type": "action_result"
//! }
//! ```
//!
//! Time anchors come from `core_input` records:
//! `payload.input.determinism.time_unix_ms`.

use crate::scan::SessionMeta;
use std::path::Path;

/// One model completion with its usage, attributed to a session.
#[derive(Debug, Clone, serde::Serialize)]
pub struct UsageEvent {
    pub session_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub parent_session_id: Option<String>,
    pub sequence: u64,
    /// Interpolated event time (unix epoch ms).
    pub timestamp_ms: u64,
    pub input_tokens: u64,
    pub output_tokens: u64,
    pub cached_input_tokens: u64,
    pub total_tokens: u64,
    pub finish_reason: String,
}

impl UsageEvent {
    /// Unique key for a journal file (session, sequence, type-ish); journal
    /// files are append-only so (session, sequence) identifies a record.
    pub fn key(&self) -> (String, u64) {
        (self.session_id.clone(), self.sequence)
    }
}

#[derive(Debug)]
struct RawUsage {
    sequence: u64,
    input_tokens: u64,
    output_tokens: u64,
    cached_input_tokens: u64,
    total_tokens: u64,
    finish_reason: String,
}

/// Parse all journal files of one session directory into usage events.
pub fn parse_session(session_dir: &Path, meta: &SessionMeta) -> Vec<UsageEvent> {
    let journal_dir = session_dir.join("journal");
    let Ok(entries) = std::fs::read_dir(&journal_dir) else {
        return Vec::new();
    };
    let mut files: Vec<_> = entries
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.extension().is_some_and(|e| e == "jsonl"))
        .collect();
    files.sort();

    let mut raw_usages: Vec<RawUsage> = Vec::new();
    let mut anchors: Vec<(u64, u64)> = Vec::new();

    for file in files {
        let Ok(content) = std::fs::read_to_string(&file) else {
            continue;
        };
        for line in content.lines() {
            if line.trim().is_empty() {
                continue;
            }
            let Ok(rec) = serde_json::from_str::<serde_json::Value>(line) else {
                continue;
            };
            let sequence = rec.get("sequence").and_then(|v| v.as_u64()).unwrap_or(0);
            let rec_type = rec.get("type").and_then(|v| v.as_str()).unwrap_or("");
            let payload = rec.get("payload");

            match rec_type {
                "core_input" => {
                    let ms = payload
                        .and_then(|p| p.get("input"))
                        .and_then(|i| i.get("determinism"))
                        .and_then(|d| d.get("time_unix_ms"))
                        .and_then(|v| v.as_u64());
                    if let Some(ms) = ms {
                        anchors.push((sequence, ms));
                    }
                }
                "action_result" => {
                    let Some(usage) = payload
                        .and_then(|p| p.get("result"))
                        .filter(|r| {
                            r.get("type").and_then(|t| t.as_str()) == Some("completion_succeeded")
                        })
                        .and_then(|r| r.get("result"))
                        .and_then(|r| r.get("usage"))
                    else {
                        continue;
                    };
                    let num = |k: &str| usage.get(k).and_then(|v| v.as_u64()).unwrap_or(0);
                    let raw = RawUsage {
                        sequence,
                        input_tokens: num("input_tokens"),
                        output_tokens: num("output_tokens"),
                        cached_input_tokens: num("cached_input_tokens"),
                        total_tokens: num("total_tokens"),
                        finish_reason: payload
                            .and_then(|p| p.get("result"))
                            .and_then(|r| r.get("result"))
                            .and_then(|r| r.get("finish_reason"))
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_string(),
                    };
                    raw_usages.push(raw);
                }
                _ => {}
            }
        }
    }

    anchors.sort_by_key(|(seq, _)| *seq);

    raw_usages
        .into_iter()
        .map(|raw| UsageEvent {
            session_id: meta.session_id.clone(),
            parent_session_id: meta.parent_session_id.clone(),
            sequence: raw.sequence,
            timestamp_ms: interpolate_time(raw.sequence, &anchors)
                .or(meta.start_time_ms)
                .unwrap_or(0),
            input_tokens: raw.input_tokens,
            output_tokens: raw.output_tokens,
            cached_input_tokens: raw.cached_input_tokens,
            total_tokens: raw.total_tokens,
            finish_reason: raw.finish_reason,
        })
        .collect()
}

/// Nearest time anchor for a record, preferring the latest anchor at or below
/// `sequence`, else the earliest anchor above it.
fn interpolate_time(sequence: u64, anchors: &[(u64, u64)]) -> Option<u64> {
    if anchors.is_empty() {
        return None;
    }
    match anchors.binary_search_by_key(&sequence, |(seq, _)| *seq) {
        Ok(i) => Some(anchors[i].1),
        Err(0) => Some(anchors[0].1),
        Err(i) => Some(anchors[i - 1].1),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn record(seq: u64, r#type: &str, body: serde_json::Value) -> String {
        serde_json::json!({
            "type": r#type,
            "sequence": seq,
            "payload": body,
        })
        .to_string()
    }

    #[test]
    fn interpolation() {
        let anchors = vec![(10, 1000u64), (20, 2000)];
        assert_eq!(interpolate_time(15, &anchors), Some(1000));
        assert_eq!(interpolate_time(10, &anchors), Some(1000));
        assert_eq!(interpolate_time(5, &anchors), Some(1000));
        assert_eq!(interpolate_time(99, &anchors), Some(2000));
        assert_eq!(interpolate_time(1, &[]), None);
    }

    #[test]
    fn parses_completion_and_ignores_echo() {
        let completion = record(
            9,
            "action_result",
            serde_json::json!({
                "action_id": "a",
                "result": {
                    "action_id": "a",
                    "result": {
                        "finish_reason": "tool_call",
                        "usage": {"input_tokens": 8619, "output_tokens": 83,
                                  "cached_input_tokens": 6656, "total_tokens": 8702}
                    },
                    "type": "completion_succeeded"
                },
                "state": "succeeded"
            }),
        );
        // Same completion echoed inside a core_input must NOT double-count.
        let anchor_ms: i64 = 1790602009248;
        let echo = record(
            10,
            "core_input",
            serde_json::json!({
                "input": {
                    "command": {
                        "result": {
                            "finish_reason": "tool_call",
                            "usage": {"input_tokens": 8619, "output_tokens": 83}
                        },
                        "type": "completion_succeeded"
                    },
                    "determinism": {"time_unix_ms": anchor_ms}
                }
            }),
        );

        let dir = std::env::temp_dir().join(format!("vibe-god-cli-test-{}", std::process::id()));
        let journal = dir.join("journal");
        std::fs::create_dir_all(&journal).unwrap();
        std::fs::write(journal.join("0000000000000005.jsonl"), format!("{completion}\n{echo}\n")).unwrap();

        let meta = SessionMeta {
            session_id: "s1".into(),
            start_time_ms: Some(1790601900000),
            ..Default::default()
        };
        let events = parse_session(&dir, &meta);
        assert_eq!(events.len(), 1);
        let e = &events[0];
        assert_eq!((e.input_tokens, e.output_tokens, e.cached_input_tokens, e.total_tokens),
                   (8619, 83, 6656, 8702));
        assert_eq!(e.timestamp_ms, 1790602009248); // interpolated from the core_input anchor
        assert_eq!(e.finish_reason, "tool_call");
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn ignores_failures_and_unrelated_records() {
        let failed = record(
            5,
            "action_result",
            serde_json::json!({
                "result": {"result": {"usage": {"input_tokens": 1}}, "type": "completion_failed"},
                "state": "failed"
            }),
        );
        let tool_result = record(
            6,
            "action_result",
            serde_json::json!({
                "result": {"result": {"output": "ls"}, "type": "success"},
                "state": "succeeded"
            }),
        );
        let malformed = "{\"type\": \"action_result\", \"sequence\": 7,"; // truncated line

        let tmp = tempfile::tempdir().unwrap();
        let journal = tmp.path().join("journal");
        std::fs::create_dir_all(&journal).unwrap();
        std::fs::write(journal.join("a.jsonl"), format!("{failed}\n{tool_result}\n{malformed}\n")).unwrap();

        let meta = SessionMeta { session_id: "s".into(), ..Default::default() };
        assert!(parse_session(tmp.path(), &meta).is_empty());
    }

    #[test]
    fn missing_usage_object_is_ignored() {
        let no_usage = record(
            3,
            "action_result",
            serde_json::json!({
                "result": {"result": {"finish_reason": "stop"}, "type": "completion_succeeded"},
                "state": "succeeded"
            }),
        );
        let tmp = tempfile::tempdir().unwrap();
        let journal = tmp.path().join("journal");
        std::fs::create_dir_all(&journal).unwrap();
        std::fs::write(journal.join("a.jsonl"), format!("{no_usage}\n")).unwrap();
        let meta = SessionMeta { session_id: "s".into(), ..Default::default() };
        assert!(parse_session(tmp.path(), &meta).is_empty());
    }

    #[test]
    fn timestamp_falls_back_to_session_start_without_anchors() {
        let completion = record(
            42,
            "action_result",
            serde_json::json!({
                "result": {
                    "result": {"finish_reason": "stop", "usage": {"input_tokens": 10, "output_tokens": 5,
                                  "cached_input_tokens": 0, "total_tokens": 15}},
                    "type": "completion_succeeded"
                }
            }),
        );
        let tmp = tempfile::tempdir().unwrap();
        let journal = tmp.path().join("journal");
        std::fs::create_dir_all(&journal).unwrap();
        std::fs::write(journal.join("a.jsonl"), format!("{completion}\n")).unwrap();
        let meta = SessionMeta { session_id: "s".into(), start_time_ms: Some(123456), ..Default::default() };
        let events = parse_session(tmp.path(), &meta);
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].timestamp_ms, 123456);
    }

    #[test]
    fn merges_journal_files_and_keeps_last_anchor() {
        let completion = record(
            100,
            "action_result",
            serde_json::json!({
                "result": {
                    "result": {"usage": {"input_tokens": 1, "output_tokens": 1,
                                  "cached_input_tokens": 0, "total_tokens": 2}},
                    "type": "completion_succeeded"
                }
            }),
        );
        // Anchors split across two files; the latest one at or below seq 100 wins.
        let anchor_old = record(50, "core_input",
            serde_json::json!({"input": {"determinism": {"time_unix_ms": 1111}}}));
        let anchor_near = record(90, "core_input",
            serde_json::json!({"input": {"determinism": {"time_unix_ms": 2222}}}));
        let anchor_after = record(150, "core_input",
            serde_json::json!({"input": {"determinism": {"time_unix_ms": 9999}}}));

        let tmp = tempfile::tempdir().unwrap();
        let journal = tmp.path().join("journal");
        std::fs::create_dir_all(&journal).unwrap();
        std::fs::write(journal.join("0000000000000001.jsonl"), format!("{anchor_old}\n{anchor_near}\n")).unwrap();
        std::fs::write(journal.join("0000000000000002.jsonl"), format!("{completion}\n{anchor_after}\n")).unwrap();

        let meta = SessionMeta { session_id: "s".into(), start_time_ms: Some(1), ..Default::default() };
        let events = parse_session(tmp.path(), &meta);
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].timestamp_ms, 2222);
    }

    #[test]
    fn missing_journal_dir_is_empty() {
        let tmp = tempfile::tempdir().unwrap();
        let meta = SessionMeta { session_id: "s".into(), ..Default::default() };
        assert!(parse_session(tmp.path(), &meta).is_empty());
    }
}
