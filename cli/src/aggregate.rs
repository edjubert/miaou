//! Aggregation of usage events.

use crate::{SessionUsage, UsageEvent};
use chrono::{DateTime, Local, TimeZone};

/// Token totals (and optionally cost) over a set of events.
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
pub struct Totals {
    pub requests: u64,
    pub input_tokens: u64,
    pub output_tokens: u64,
    pub cached_input_tokens: u64,
    pub total_tokens: u64,
    /// Estimated cost in USD, when a price table is available.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cost_usd: Option<f64>,
}

impl Totals {
    pub fn from_events<'a>(events: impl Iterator<Item = &'a UsageEvent>) -> Self {
        let mut t = Totals::default();
        for e in events {
            t.requests += 1;
            t.input_tokens += e.input_tokens;
            t.output_tokens += e.output_tokens;
            t.cached_input_tokens += e.cached_input_tokens;
            t.total_tokens += e.total_tokens;
        }
        t
    }

    pub fn add(&mut self, other: &Totals) {
        self.requests += other.requests;
        self.input_tokens += other.input_tokens;
        self.output_tokens += other.output_tokens;
        self.cached_input_tokens += other.cached_input_tokens;
        self.total_tokens += other.total_tokens;
        self.cost_usd = match (self.cost_usd, other.cost_usd) {
            (Some(a), Some(b)) => Some(a + b),
            (Some(a), None) | (None, Some(a)) => Some(a),
            (None, None) => None,
        };
    }
}

/// A named aggregation row.
#[derive(Debug, Clone, serde::Serialize)]
pub struct Row {
    pub key: String,
    pub sessions: u64,
    #[serde(flatten)]
    pub totals: Totals,
}

fn local_date(ms: u64) -> String {
    Local
        .timestamp_millis_opt(ms as i64)
        .single()
        .unwrap_or_else(Local::now)
        .format("%Y-%m-%d")
        .to_string()
}

pub fn event_time(e: &UsageEvent) -> DateTime<Local> {
    Local
        .timestamp_millis_opt(e.timestamp_ms as i64)
        .single()
        .unwrap_or_else(Local::now)
}

/// Aggregate all events by local calendar day.
pub fn aggregate_daily(sessions: &[SessionUsage]) -> Vec<Row> {
    let mut rows: std::collections::BTreeMap<String, Row> = Default::default();
    for s in sessions {
        let mut seen = std::collections::HashSet::new();
        for e in &s.events {
            let day = local_date(e.timestamp_ms);
            let row = rows.entry(day.clone()).or_insert_with(|| Row {
                key: day.clone(),
                sessions: 0,
                totals: Totals::default(),
            });
            if seen.insert(day) {
                row.sessions += 1;
            }
            row.totals.requests += 1;
            row.totals.input_tokens += e.input_tokens;
            row.totals.output_tokens += e.output_tokens;
            row.totals.cached_input_tokens += e.cached_input_tokens;
            row.totals.total_tokens += e.total_tokens;
        }
    }
    rows.into_values().collect()
}

/// Aggregate by project (basename of the session's working directory).
pub fn aggregate_by_project(sessions: &[SessionUsage]) -> Vec<Row> {
    let mut rows: std::collections::BTreeMap<String, Row> = Default::default();
    for s in sessions {
        let key = s
            .meta
            .cwd
            .as_deref()
            .map(|c| c.rsplit('/').next().unwrap_or(c))
            .unwrap_or("(unknown)")
            .to_string();
        let row = rows.entry(key.clone()).or_insert_with(|| Row {
            key,
            sessions: 0,
            totals: Totals::default(),
        });
        row.sessions += 1;
        let t = s.totals();
        row.totals.add(&t);
    }
    rows.into_values().collect()
}

/// Per-session rows, newest first.
pub fn aggregate_by_session(sessions: &[SessionUsage]) -> Vec<SessionRow> {
    let mut rows: Vec<SessionRow> = sessions
        .iter()
        .map(|s| SessionRow {
            session_id: s.meta.session_id.clone(),
            short_id: s.meta.session_id[..8.min(s.meta.session_id.len())].to_string(),
            project: s
                .meta
                .cwd
                .as_deref()
                .map(|c| c.rsplit('/').next().unwrap_or(c))
                .unwrap_or("(unknown)")
                .to_string(),
            title: s.meta.title.clone(),
            subagent: s.meta.parent_session_id.is_some(),
            started_ms: s.meta.start_time_ms,
            totals: s.totals(),
        })
        .filter(|r| r.totals.requests > 0)
        .collect();
    rows.sort_by_key(|r| std::cmp::Reverse(r.started_ms.unwrap_or(0)));
    rows
}

/// Per-session aggregate row (session metadata joined with totals).
#[derive(Debug, Clone, serde::Serialize)]
pub struct SessionRow {
    pub session_id: String,
    pub short_id: String,
    pub project: String,
    pub title: Option<String>,
    pub subagent: bool,
    pub started_ms: Option<u64>,
    #[serde(flatten)]
    pub totals: Totals,
}
