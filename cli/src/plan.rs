//! Plan information from Vibe's local whoami cache.
//!
//! `~/.vibe/whoami_cache.json` is written by Vibe itself (TTL ~6h, keyed by
//! account) and holds the `/whoami` response: plan type and name. Reading it
//! needs no network call and no credential handling.

use std::path::Path;

/// Plan fields as cached by Vibe's `/whoami`.
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
pub struct PlanInfo {
    /// `api`, `chat` or `mistral_code` (Vibe's `AccountPlanKind`).
    pub plan_type: Option<String>,
    /// e.g. `INDIVIDUAL`.
    pub plan_name: Option<String>,
    pub organization_kind: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub customer_id: Option<String>,
    /// When Vibe cached this entry (unix seconds).
    pub stored_at_timestamp: Option<u64>,
}

impl PlanInfo {
    pub fn describe(&self) -> String {
        let name = self.plan_name.as_deref().unwrap_or("unknown");
        let kind = self.plan_type.as_deref().unwrap_or("?");
        format!("{name} ({kind})")
    }
}

/// Read the most recently cached plan entry from `<vibe_home>/whoami_cache.json`.
/// Returns `None` when the cache is absent or empty.
pub fn read_cached(vibe_home: &Path) -> Option<PlanInfo> {
    let raw = std::fs::read_to_string(vibe_home.join("whoami_cache.json")).ok()?;
    let root: serde_json::Value = serde_json::from_str(&raw).ok()?;
    let entries = root.as_object()?;
    entries
        .iter()
        .filter_map(|(_key, entry)| {
            let payload = entry.get("payload")?;
            Some(PlanInfo {
                plan_type: payload.get("plan_type").and_then(|v| v.as_str()).map(str::to_owned),
                plan_name: payload.get("plan_name").and_then(|v| v.as_str()).map(str::to_owned),
                organization_kind: payload
                    .get("organization_kind")
                    .and_then(|v| v.as_str())
                    .map(str::to_owned),
                customer_id: payload.get("customer_id").and_then(|v| v.as_str()).map(str::to_owned),
                stored_at_timestamp: entry
                    .get("stored_at_timestamp")
                    .and_then(|v| v.as_u64()),
            })
        })
        .max_by_key(|p| p.stored_at_timestamp.unwrap_or(0))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn write_cache(home: &Path, content: &str) {
        std::fs::create_dir_all(home).unwrap();
        std::fs::write(home.join("whoami_cache.json"), content).unwrap();
    }

    #[test]
    fn reads_most_recent_entry() {
        let tmp = tempfile::tempdir().unwrap();
        write_cache(
            tmp.path(),
            r#"{
              "stale": {
                "stored_at_timestamp": 1000,
                "payload": {"plan_type": "api", "plan_name": "OLD"}
              },
              "fresh": {
                "stored_at_timestamp": 2000,
                "payload": {
                  "plan_type": "chat",
                  "plan_name": "INDIVIDUAL",
                  "organization_kind": "S",
                  "customer_id": "cf39155d",
                  "prompt_switching_to_pro_plan": false
                }
              }
            }"#,
        );
        let plan = read_cached(tmp.path()).expect("cache parses");
        assert_eq!(plan.plan_type.as_deref(), Some("chat"));
        assert_eq!(plan.plan_name.as_deref(), Some("INDIVIDUAL"));
        assert_eq!(plan.organization_kind.as_deref(), Some("S"));
        assert_eq!(plan.customer_id.as_deref(), Some("cf39155d"));
        assert_eq!(plan.stored_at_timestamp, Some(2000));
        assert_eq!(plan.describe(), "INDIVIDUAL (chat)");
    }

    #[test]
    fn tolerates_missing_or_broken_cache() {
        let tmp = tempfile::tempdir().unwrap();
        assert!(read_cached(tmp.path()).is_none());
        write_cache(tmp.path(), "not json");
        assert!(read_cached(tmp.path()).is_none());
        write_cache(tmp.path(), "{}");
        assert!(read_cached(tmp.path()).is_none());
    }
}
