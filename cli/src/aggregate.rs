//! Aggregation of usage events.

use crate::dates::{local_ym, local_ymd};
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

pub fn event_time(e: &UsageEvent) -> DateTime<Local> {
    Local
        .timestamp_millis_opt(e.timestamp_ms as i64)
        .single()
        .unwrap_or_else(Local::now)
}

/// Aggregate all events by a period key (e.g. `YYYY-MM-DD`, `YYYY-MM`).
/// `sessions` counts, per bucket, the number of distinct sessions active in it.
pub fn aggregate_by_period(
    sessions: &[SessionUsage],
    key_of: impl Fn(u64) -> String,
) -> Vec<Row> {
    let mut rows: std::collections::BTreeMap<String, Row> = Default::default();
    for s in sessions {
        let mut seen = std::collections::HashSet::new();
        for e in &s.events {
            let key = key_of(e.timestamp_ms);
            let row = rows.entry(key.clone()).or_insert_with(|| Row {
                key: key.clone(),
                sessions: 0,
                totals: Totals::default(),
            });
            if seen.insert(key) {
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

/// Aggregate all events by local calendar day.
pub fn aggregate_daily(sessions: &[SessionUsage]) -> Vec<Row> {
    aggregate_by_period(sessions, local_ymd)
}

/// Aggregate all events by local calendar month (`YYYY-MM`).
/// This is the "reset" view for monthly plans: each month starts at zero.
pub fn aggregate_monthly(sessions: &[SessionUsage]) -> Vec<Row> {
    aggregate_by_period(sessions, local_ym)
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::scan::SessionMeta;

    fn event(ts: u64, input: u64, output: u64) -> UsageEvent {
        UsageEvent {
            session_id: "s".into(),
            parent_session_id: None,
            sequence: 0,
            timestamp_ms: ts,
            input_tokens: input,
            output_tokens: output,
            cached_input_tokens: 0,
            total_tokens: input + output,
            finish_reason: "stop".into(),
        }
    }

    fn session(id: &str, cwd: Option<&str>, start: u64, events: Vec<UsageEvent>) -> SessionUsage {
        SessionUsage {
            meta: SessionMeta {
                session_id: id.into(),
                cwd: cwd.map(str::to_owned),
                start_time_ms: Some(start),
                parent_session_id: None,
                ..Default::default()
            },
            events,
        }
    }

    #[test]
    fn totals_sum_tokens() {
        let evs = [event(0, 100, 10), event(0, 50, 5)];
        let t = Totals::from_events(evs.iter());
        assert_eq!(t.requests, 2);
        assert_eq!(t.input_tokens, 150);
        assert_eq!(t.output_tokens, 15);
        assert_eq!(t.total_tokens, 165);
        assert_eq!(t.cached_input_tokens, 0);
    }

    #[test]
    fn add_merges_cost_when_both_sides_priced() {
        let mut a = Totals { requests: 1, cost_usd: Some(0.5), ..Default::default() };
        let b = Totals { requests: 2, cost_usd: Some(1.5), ..Default::default() };
        a.add(&b);
        assert_eq!(a.requests, 3);
        assert_eq!(a.cost_usd, Some(2.0));

        // One side unpriced keeps the priced value.
        let mut c = Totals::default();
        c.add(&b);
        assert_eq!(c.cost_usd, Some(1.5));

        let mut d = Totals { cost_usd: Some(1.0), ..Default::default() };
        d.add(&Totals::default());
        assert_eq!(d.cost_usd, Some(1.0));
    }

    #[test]
    fn daily_groups_by_local_date_and_counts_sessions() {
        // Local noons: stable within a calendar day in any timezone
        // (DST transitions happen at night, never between noon hours).
        let noon = |days_ahead: i64| {
            let date = chrono::Local::now().date_naive() + chrono::Duration::days(days_ahead);
            let naive = date.and_hms_opt(12, 0, 0).unwrap();
            naive
                .and_local_timezone(chrono::Local)
                .single()
                .unwrap()
                .timestamp_millis() as u64
        };
        let noon0 = noon(0);
        let noon2 = noon(2);

        let a = session("a", None, noon0, vec![event(noon0, 10, 1), event(noon0 + 3_600_000, 20, 2)]);
        let b = session("b", None, noon0, vec![event(noon0, 30, 3)]);
        let c = session("c", None, noon2, vec![event(noon2, 40, 4)]);

        let rows = aggregate_daily(&[a, b, c]);
        let by_key: std::collections::BTreeMap<_, _> =
            rows.iter().map(|r| (r.key.clone(), r.clone())).collect();

        // Day of noon0: sessions a and b, 3 requests.
        let row0 = &by_key[&local_ymd(noon0)];
        assert_eq!(row0.sessions, 2);
        assert_eq!(row0.totals.requests, 3);
        assert_eq!(row0.totals.input_tokens, 60);
        assert_eq!(row0.totals.output_tokens, 6);

        // Day of noon2: session c alone. noon1 has no events, so only 2 buckets.
        let row2 = &by_key[&local_ymd(noon2)];
        assert_eq!(row2.sessions, 1);
        assert_eq!(row2.totals.requests, 1);
        assert_eq!(rows.len(), 2);
    }

    #[test]
    fn monthly_buckets_reset_at_month_boundaries() {
        use chrono::Datelike;
        // Local noons on the 1st of two consecutive months.
        let noon_first = |months_ahead: i64| {
            let today = chrono::Local::now().date_naive();
            let date = today
                .with_day(1)
                .unwrap()
                .checked_add_months(chrono::Months::new(months_ahead as u32))
                .unwrap();
            let naive = date.and_hms_opt(12, 0, 0).unwrap();
            naive
                .and_local_timezone(chrono::Local)
                .single()
                .unwrap()
                .timestamp_millis() as u64
        };
        let this_month = noon_first(0);
        let next_month = noon_first(1);

        // Same session spanning two months: requests split per month,
        // and each month bucket counts the session once.
        let a = session("a", None, this_month, vec![
            event(this_month, 10, 1),
            event(this_month + 3_600_000, 20, 2),
            event(next_month, 40, 4),
        ]);
        let rows = aggregate_monthly(std::slice::from_ref(&a));
        assert_eq!(rows.len(), 2);

        let m0 = rows.iter().find(|r| r.key == local_ym(this_month)).unwrap();
        assert_eq!(m0.sessions, 1);
        assert_eq!(m0.totals.requests, 2);
        assert_eq!(m0.totals.input_tokens, 30);
        assert_eq!(m0.totals.output_tokens, 3);

        let m1 = rows.iter().find(|r| r.key == local_ym(next_month)).unwrap();
        assert_eq!(m1.sessions, 1);
        assert_eq!(m1.totals.requests, 1);
        assert_eq!(m1.totals.input_tokens, 40);

        // A second session in the same month bumps the session count only there.
        let b = session("b", None, this_month, vec![event(this_month, 50, 5)]);
        let rows = aggregate_monthly(&[a, b]);
        let m0 = rows.iter().find(|r| r.key == local_ym(this_month)).unwrap();
        assert_eq!(m0.sessions, 2);
        assert_eq!(m0.totals.requests, 3);
    }

    #[test]
    fn projects_use_cwd_basename_and_unknown_fallback() {
        let a = session("a", Some("/home/me/proj-x"), 0, vec![event(0, 10, 1)]);
        let b = session("b", Some("/home/me/proj-x/sub"), 0, vec![event(0, 20, 2)]);
        let c = session("c", None, 0, vec![event(0, 30, 3)]);

        let rows = aggregate_by_project(&[a, b, c]);
        let find = |k: &str| rows.iter().find(|r| r.key == k).unwrap();

        assert_eq!(find("proj-x").sessions, 1);
        assert_eq!(find("proj-x").totals.input_tokens, 10);
        assert_eq!(find("sub").sessions, 1); // basename, not path
        assert_eq!(find("(unknown)").totals.input_tokens, 30);
    }

    #[test]
    fn session_rows_skip_empty_and_sort_newest_first() {
        let older = session("older", Some("/p/aaa"), 100, vec![event(100, 10, 1)]);
        let newer = session("newer", Some("/p/bbb"), 200, vec![event(200, 20, 2)]);
        let empty = session("empty", Some("/p/ccc"), 300, vec![]);

        let mut rows = aggregate_by_session(&[older, newer, empty]);
        assert_eq!(rows.len(), 2); // empty session filtered out
        rows.sort_by_key(|r| std::cmp::Reverse(r.started_ms.unwrap_or(0)));
        assert_eq!(rows[0].session_id, "newer");
        assert_eq!(rows[0].project, "bbb");
        assert_eq!(rows[0].totals.requests, 1);
        assert!(!rows[0].subagent);
    }

    #[test]
    fn session_row_flags_subagent() {
        let mut s = session("kid", Some("/p"), 0, vec![event(0, 1, 1)]);
        s.meta.parent_session_id = Some("parent".into());
        let rows = aggregate_by_session(&[s]);
        assert!(rows[0].subagent);
        assert_eq!(rows[0].short_id, "kid");
    }
}
