//! Token price calibration against the Mistral Console.
//!
//! The Console gives the authoritative cost for a UTC period; local
//! journals give the token mix for the same period. Each observation is
//! one equation of a linear system with three unknowns, the coefficients
//! on (input, cached, output) tokens:
//!
//!   cost_i = (in_i * A + cached_i * B + out_i * C) / 1e6
//!
//! The tracker bills with the convention "cached tokens are a discounted
//! part of input": cost = (in - cached) * ip + cached * cp + out * op,
//! which is the same family with A = ip, B = cp - ip, C = op. The solver
//! fits A, B, C once and reports the config prices as
//! input_price = A, cached_input_price = A + B, output_price = C.
//!
//! Observations are stored in `~/.config/vibe-god-cli/calibration.toml`.
//! Each entry records the token mix *at add time* so the ledger stays
//! stable even as journals grow.

use crate::dates::utc_ym;
use crate::SessionUsage;
use std::path::Path;

#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct Observation {
    /// Console period end (epoch ms, UTC).
    pub at_ms: u64,
    /// Cost reported by the Console for the month, in the display currency.
    pub cost: f64,
    pub input_tokens: u64,
    pub output_tokens: u64,
    pub cached_input_tokens: u64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Solution {
    /// Fitted coefficient per input token (also config input_price).
    pub input_price: f64,
    /// Fitted coefficient per cached token, interpreted as the premium
    /// over input_price: config cached_input_price = input_price + delta.
    pub cached_delta: f64,
    /// Config cached_input_price, ready to paste.
    pub cached_input_price: f64,
    pub output_price: f64,
    /// (observed - predicted) per observation, in cost units.
    pub residuals: Vec<f64>,
    pub rms: f64,
}

/// Token mix of the current UTC month, strictly at or before `at_ms`.
/// The Console period starts at 00:00 UTC on the first of the month.
pub fn month_tokens_at(sessions: &[SessionUsage], at_ms: u64) -> Observation {
    let month = utc_ym(at_ms);
    let mut input = 0u64;
    let mut output = 0u64;
    let mut cached = 0u64;
    for s in sessions {
        for e in &s.events {
            if e.timestamp_ms <= at_ms && utc_ym(e.timestamp_ms) == month {
                input += e.input_tokens;
                output += e.output_tokens;
                cached += e.cached_input_tokens;
            }
        }
    }
    Observation {
        at_ms,
        cost: 0.0,
        input_tokens: input,
        output_tokens: output,
        cached_input_tokens: cached,
    }
}

/// Latest console observation inside the current month: the authoritative
/// envelope position. Local tokens cannot reproduce it (invisible usage on
/// other surfaces, plan accounting), so the budget anchors on it.
pub fn latest_anchor_cost(observations: &[Observation], ym: &str, now_ms: u64) -> Option<Observation> {
    use crate::dates::utc_ym;
    observations
        .iter()
        .filter(|o| utc_ym(o.at_ms) == ym && o.at_ms <= now_ms)
        .max_by_key(|o| o.at_ms)
        .cloned()
}

/// Incremental console cost per locally observed token: measured on the
/// most recent consecutive pair of observations (cost delta / local
/// token delta). The blended month rate is inflated by invisible usage
/// from other surfaces; the incremental rate is what the current usage
/// actually costs per local token, and the best predictor between
/// observations. Falls back to the most recent pair from any month so
/// a fresh month inherits yesterday's rate until it gets its own pairs.
pub fn incremental_rate(observations: &[Observation]) -> Option<f64> {
    let mut sorted: Vec<&Observation> = observations.iter().collect();
    sorted.sort_by_key(|o| o.at_ms);
    let mut best: Option<f64> = None;
    for pair in sorted.windows(2) {
        let (prev, last) = (pair[0], pair[1]);
        let token_delta =
            (last.input_tokens + last.output_tokens).saturating_sub(prev.input_tokens + prev.output_tokens);
        let cost_delta = last.cost - prev.cost;
        if token_delta > 0 && cost_delta >= 0.0 {
            best = Some(cost_delta * 1e6 / token_delta as f64);
        }
    }
    best
}

/// Console-anchored month cost with a live delta: the latest observation
/// cost plus local tokens consumed since that observation, valued at the
/// incremental rate. Moves between observations, re-anchors on each one.
/// Without an observation in the current month, the month tokens are
/// valued directly at the inherited incremental rate (yesterday's pair):
/// a fresh month starts at zero and the rate carries over.
pub fn anchored_cost_with_delta(
    observations: &[Observation],
    sessions: &[SessionUsage],
    ym: &str,
    now_ms: u64,
) -> Option<f64> {
    use crate::dates::utc_ym;
    let rate = incremental_rate(observations)?;
    let month_tokens = |after: Option<u64>| -> u64 {
        sessions
            .iter()
            .flat_map(|s| s.events.iter())
            .filter(|e| {
                utc_ym(e.timestamp_ms) == ym
                    && after.is_none_or(|a| e.timestamp_ms > a)
            })
            .map(|e| e.input_tokens + e.output_tokens)
            .sum()
    };
    match latest_anchor_cost(observations, ym, now_ms) {
        Some(anchor) => {
            Some(anchor.cost + month_tokens(Some(anchor.at_ms)) as f64 * rate / 1e6)
        }
        // No anchor this month yet: zero + tokens at the inherited rate.
        None => Some(month_tokens(None) as f64 * rate / 1e6),
    }
}

/// Cost of one local day, valued at the incremental rate measured by the
/// ledger: the same rate that drives the live delta of the anchored month
/// cost, so day and month figures agree. Falls back to the caller when no
/// rate is available.
pub fn anchored_day_cost(observations: &[Observation], day_tokens: u64) -> Option<f64> {
    let rate = incremental_rate(observations)?;
    Some(day_tokens as f64 * rate / 1e6)
}

/// Ledger location: `<config dir>/calibration.toml`.
pub fn ledger_path() -> std::path::PathBuf {
    crate::budget::default_config_path()
        .parent()
        .map(|p| p.join("calibration.toml"))
        .unwrap_or_else(|| std::path::PathBuf::from("calibration.toml"))
}

/// Month-to-date totals with compaction repair. Vibe compaction deletes
/// journal history that the archive never saw; each ledger observation
/// taken inside the month provides a token floor at its timestamp. The
/// estimate is the max of the archive scan and, per observation,
/// snapshot tokens + events recorded after the observation time.
/// Request counts cannot be reconstructed from snapshots: the best
/// available count is kept.
pub fn floored_month_totals(
    sessions: &[SessionUsage],
    ym: &str,
    now_ms: u64,
    observations: &[Observation],
) -> crate::Totals {
    use crate::dates::utc_ym;
    let month_events = || {
        sessions
            .iter()
            .flat_map(|s| s.events.iter())
            .filter(|e| utc_ym(e.timestamp_ms) == ym)
    };
    let mut best = crate::Totals::from_events(month_events());
    for o in observations
        .iter()
        .filter(|o| utc_ym(o.at_ms) == ym && o.at_ms <= now_ms)
    {
        let after = crate::Totals::from_events(
            month_events().filter(|e| e.timestamp_ms > o.at_ms),
        );
        let mut floored = crate::Totals {
            requests: after.requests,
            input_tokens: o.input_tokens,
            output_tokens: o.output_tokens,
            cached_input_tokens: o.cached_input_tokens,
            total_tokens: o.input_tokens + o.output_tokens,
            cost_usd: None,
        };
        floored.add(&after);
        if floored.total_tokens > best.total_tokens {
            best = floored;
        }
    }
    best
}

/// Ledger stored as `[[observations]]` in TOML.
pub fn load_ledger(path: &Path) -> Vec<Observation> {
    let raw = std::fs::read_to_string(path).unwrap_or_default();
    let Ok(value) = raw.parse::<toml::Value>() else {
        return Vec::new();
    };
    value
        .get("observations")
        .and_then(|v| v.as_array())
        .map(|a| {
            a.iter()
                .filter_map(|o| {
                    Some(Observation {
                        at_ms: o.get("at_ms")?.as_integer()? as u64,
                        cost: o.get("cost")?.as_float()?,
                        input_tokens: o.get("input_tokens")?.as_integer()? as u64,
                        output_tokens: o.get("output_tokens")?.as_integer()? as u64,
                        cached_input_tokens: o.get("cached_input_tokens")?.as_integer()? as u64,
                    })
                })
                .collect()
        })
        .unwrap_or_default()
}

pub fn append_ledger(path: &Path, observation: &Observation) -> std::io::Result<()> {
    let mut all = load_ledger(path);
    all.push(observation.clone());
    all.sort_by_key(|o| o.at_ms);
    let mut doc = String::from("# vibe-god-cli calibration ledger. Managed by `calibrate add`.\n\n");
    for o in &all {
        doc.push_str(&format!(
            "[[observations]]\nat_ms = {}\ncost = {}\ninput_tokens = {}\noutput_tokens = {}\ncached_input_tokens = {}\n\n",
            o.at_ms, o.cost, o.input_tokens, o.output_tokens, o.cached_input_tokens
        ));
    }
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(path, doc)
}

/// Solve a 3x3 linear system by Gaussian elimination with partial pivoting.
fn solve3(mut a: [[f64; 3]; 3], mut b: [f64; 3]) -> Option<[f64; 3]> {
    for col in 0..3 {
        let pivot = (col..3).max_by(|i, j| a[*i][col].abs().partial_cmp(&a[*j][col].abs()).unwrap())?;
        if a[pivot][col].abs() < 1e-12 {
            return None; // singular: observations are not independent
        }
        a.swap(col, pivot);
        b.swap(col, pivot);
        for row in (col + 1)..3 {
            let factor = a[row][col] / a[col][col];
            let pivot_row = a[col];
            for k in col..3 {
                a[row][k] -= factor * pivot_row[k];
            }
            b[row] -= factor * b[col];
        }
    }
    let mut x = [0.0; 3];
    for row in (0..3).rev() {
        let mut acc = b[row];
        for k in (row + 1)..3 {
            acc -= a[row][k] * x[k];
        }
        x[row] = acc / a[row][row];
    }
    Some(x)
}

/// Least-squares fit (normal equations) of the three token coefficients,
/// on the DELTAS between consecutive observations.
///
/// Deltas, not absolute costs: the Console month total includes usage that
/// never touched this machine (web, mobile, remote agents, pruned
/// sessions), which local journals cannot attribute. Between two
/// observations taken close in time, all usage is assumed to be local:
///
///   cost_i - cost_{i-1} = (d_in * A + d_cached * B + d_out * C) / 1e6
///
/// The first observation only serves as the baseline. Returns `None`
/// when the deltas do not constrain the three unknowns independently
/// (fewer than 2 usable pairs, or degenerate token mixes).
pub fn solve(observations: &[Observation]) -> Option<Solution> {
    let mut sorted = observations.to_vec();
    sorted.sort_by_key(|o| o.at_ms);
    let deltas: Vec<(f64, [f64; 3])> = sorted
        .windows(2)
        .filter_map(|w| {
            let (prev, cur) = (&w[0], &w[1]);
            let d_cost = cur.cost - prev.cost;
            if d_cost < 0.0 {
                return None; // non-monotonic cost: unusable pair
            }
            Some((
                d_cost,
                [
                    (cur.input_tokens.saturating_sub(prev.input_tokens)) as f64 / 1e6,
                    (cur.cached_input_tokens.saturating_sub(prev.cached_input_tokens)) as f64 / 1e6,
                    (cur.output_tokens.saturating_sub(prev.output_tokens)) as f64 / 1e6,
                ],
            ))
        })
        .collect();
    if deltas.len() < 3 {
        return None;
    }
    let mut c = [[0.0f64; 3]; 3];
    let mut d = [0.0f64; 3];
    for (d_cost, row) in &deltas {
        for i in 0..3 {
            for j in 0..3 {
                c[i][j] += row[i] * row[j];
            }
            d[i] += row[i] * d_cost;
        }
    }
    let [a, b, out] = solve3(c, d)?;
    let residuals: Vec<f64> = deltas
        .iter()
        .map(|(d_cost, row)| d_cost - (row[0] * a + row[1] * b + row[2] * out))
        .collect();
    let rms = (residuals.iter().map(|r| r * r).sum::<f64>() / residuals.len() as f64).sqrt();
    Some(Solution {
        input_price: a,
        cached_delta: b,
        cached_input_price: a + b,
        output_price: out,
        residuals,
        rms,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::UsageEvent;

    fn obs(at_ms: u64, input: u64, cached: u64, output: u64, cost: f64) -> Observation {
        Observation {
            at_ms,
            cost,
            input_tokens: input,
            output_tokens: output,
            cached_input_tokens: cached,
        }
    }

    #[test]
    fn ledger_round_trip() {
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("calibration.toml");
        let o = obs(1, 100, 50, 10, 0.5);
        append_ledger(&path, &o).unwrap();
        // Second entry with an earlier timestamp lands first (sorted).
        append_ledger(&path, &obs(0, 10, 0, 1, 0.05)).unwrap();
        let all = load_ledger(&path);
        assert_eq!(all.len(), 2);
        assert_eq!(all[0].at_ms, 0);
        assert_eq!(all[1], o);
    }

    #[test]
    fn recovers_prices_from_delta_observations() {
        // Simulated console costs: month total with an unattributable
        // 2.0 offset (usage invisible locally before the baseline), then
        // four observations with increasing local-only usage.
        let ip = 1.4;
        let cp = 0.26;
        let op = 4.4;
        let offset = 2.0; // must NOT bias the fit: deltas cancel it
        let steps = [(10_000, 8_000, 200), (20_000, 5_000, 900), (5_000, 0, 50), (30_000, 29_000, 1_500)];
        let mut obs_list = vec![obs(0, 0, 0, 0, offset)]; // baseline
        let (mut tin, mut tcache, mut tout, mut tcost) = (0u64, 0u64, 0u64, offset);
        for (i, &(inp, cached, out)) in steps.iter().enumerate() {
            tin += inp;
            tcache += cached;
            tout += out;
            tcost += ((inp - cached) as f64 * ip + cached as f64 * cp + out as f64 * op) / 1e6;
            obs_list.push(obs(1_000 + i as u64, tin, tcache, tout, tcost));
        }
        let s = solve(&obs_list).expect("solvable");
        assert!((s.input_price - ip).abs() < 1e-6, "{}", s.input_price);
        assert!((s.cached_input_price - cp).abs() < 1e-6, "{}", s.cached_input_price);
        assert!((s.output_price - op).abs() < 1e-6, "{}", s.output_price);
        assert!(s.rms < 1e-9, "{}", s.rms);
    }

    #[test]
    fn degenerate_or_insufficient_deltas_are_rejected() {
        // Fewer than 4 observations (3 usable deltas... here 2 deltas max).
        let o = obs(1, 10_000, 8_000, 200, 0.5);
        assert!(solve(&[o.clone(), o.clone(), o.clone()]).is_none());
        // Identical mixes: the delta system is singular.
        let a = obs(1, 0, 0, 0, 0.0);
        let b = obs(2, 10_000, 8_000, 200, 0.5);
        let c = obs(3, 20_000, 16_000, 400, 1.0);
        let d = obs(4, 30_000, 24_000, 600, 1.5);
        assert!(solve(&[a, b, c, d]).is_none());
    }

    #[test]
    fn floored_month_totals_restores_lost_history() {
        use crate::UsageEvent;
        fn ev(ts: u64, input: u64) -> UsageEvent {
            UsageEvent { session_id: "s".into(), parent_session_id: None, sequence: ts,
                timestamp_ms: ts, input_tokens: input, output_tokens: 1,
                cached_input_tokens: 0, total_tokens: input + 1, finish_reason: "stop".into() }
        }
        // Archive view: only 30 tokens survived compaction.
        let sessions = vec![SessionUsage {
            meta: crate::scan::SessionMeta { session_id: "s".into(), ..Default::default() },
            events: vec![ev(1_000, 10), ev(2_000, 20)],
        }];
        // Snapshot taken at t=1500 recorded 100 input tokens (before the loss).
        let obs = vec![obs(1_500, 100, 90, 5, 1.5)];
        let totals = floored_month_totals(&sessions, "1970-01", 9_999, &obs);
        // Floor: snapshot 100 + events after t=1500 (20) = 120 > archive 30.
        assert_eq!(totals.input_tokens, 120);
        assert_eq!(totals.output_tokens, 6);
    }

    #[test]
    fn anchored_cost_moves_with_local_delta() {
        use crate::UsageEvent;
        fn ev(seq: u64, ts: u64, input: u64, output: u64) -> UsageEvent {
            UsageEvent { session_id: "s".into(), parent_session_id: None, sequence: seq,
                timestamp_ms: ts, input_tokens: input, output_tokens: output,
                cached_input_tokens: 0, total_tokens: input + output, finish_reason: "stop".into() }
        }
        // January pair: 50 at 11M total tokens, then 55 at 11.5M:
        // incremental rate = 5 / 0.5M = 10 EUR/M (not the blended rate).
        let january = [
            obs(1_000, 10_000_000, 9_000_000, 1_000_000, 50.0),
            obs(1_500, 10_000_000, 9_000_000, 1_500_000, 55.0),
        ];
        assert!((incremental_rate(&january).unwrap() - 10.0).abs() < 1e-9);

        let february_1st = 2_678_400_000u64;
        let events = vec![
            // January, before the anchor: not in the delta.
            ev(1, 1_000, 5_000_000, 100_000),
            // January, after the anchor: 2M.
            ev(10, 2_000, 800_000, 200_000),
            ev(11, 3_000, 800_000, 200_000),
            // February: 4M.
            ev(12, february_1st + 1_000, 1_500_000, 500_000),
            ev(13, february_1st + 2_000, 1_500_000, 500_000),
        ];
        let sessions = vec![SessionUsage {
            meta: crate::scan::SessionMeta { session_id: "s".into(), ..Default::default() },
            events,
        }];

        // Anchored month: 55 + 2M after the anchor at 10 EUR/M = 75.
        let cost = anchored_cost_with_delta(&january, &sessions, "1970-01", 9_999_999).unwrap();
        assert!((cost - 75.0).abs() < 1e-9, "{cost}");

        // Fresh month (no observation in it): 4M tokens at the inherited
        // rate 10 EUR/M = 40.
        let fresh = anchored_cost_with_delta(&january, &sessions, "1970-02", 9_999_999).unwrap();
        assert!((fresh - 40.0).abs() < 1e-9, "{fresh}");

        // Single observation, no pair: no rate at all.
        assert!(anchored_cost_with_delta(&january[..1], &sessions, "1970-02", 9_999_999).is_none());
        // No observations: None (caller falls back to config prices).
        assert!(anchored_cost_with_delta(&[], &sessions, "1970-02", 9_999_999).is_none());
    }

    #[test]
    fn anchored_day_cost_uses_the_incremental_rate() {
        // Same January pair as anchored_cost_moves_with_local_delta:
        // incremental rate = 10 EUR/M.
        let january = [
            obs(1_000, 10_000_000, 9_000_000, 1_000_000, 50.0),
            obs(1_500, 10_000_000, 9_000_000, 1_500_000, 55.0),
        ];
        // A day of 3M tokens costs 30 at that rate.
        assert!((anchored_day_cost(&january, 3_000_000).unwrap() - 30.0).abs() < 1e-9);
        // No pair, no rate.
        assert!(anchored_day_cost(&january[..1], 3_000_000).is_none());
    }

    #[test]
    fn month_tokens_at_respects_utc_month_and_cutoff() {
        let events = vec![
            UsageEvent { session_id: "s".into(), parent_session_id: None, sequence: 1,
                timestamp_ms: 1_700_000_000_000, input_tokens: 10, output_tokens: 1,
                cached_input_tokens: 5, total_tokens: 11, finish_reason: "stop".into() },
            // After the cutoff: excluded.
            UsageEvent { session_id: "s".into(), parent_session_id: None, sequence: 2,
                timestamp_ms: 1_700_000_060_000, input_tokens: 100, output_tokens: 10,
                cached_input_tokens: 50, total_tokens: 110, finish_reason: "stop".into() },
        ];
        let sessions = vec![SessionUsage {
            meta: crate::scan::SessionMeta { session_id: "s".into(), ..Default::default() },
            events,
        }];
        let o = month_tokens_at(&sessions, 1_700_000_030_000);
        assert_eq!((o.input_tokens, o.output_tokens, o.cached_input_tokens), (10, 1, 5));
    }
}
