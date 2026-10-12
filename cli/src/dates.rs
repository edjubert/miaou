//! Local-date helpers shared by the CLI and aggregations.

use chrono::TimeZone;

/// Parse `YYYY-MM-DD` as the first local millisecond of that day.
pub fn parse_local_date_start(s: &str) -> Option<u64> {
    chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d")
        .ok()?
        .and_hms_opt(0, 0, 0)?
        .and_local_timezone(chrono::Local)
        .single()
        .map(|dt| dt.timestamp_millis().max(0) as u64)
}

/// Parse `YYYY-MM-DD` as the first local millisecond of the next day
/// (exclusive upper bound, so `--until` includes the whole day).
pub fn parse_local_date_end(s: &str) -> Option<u64> {
    chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d")
        .ok()?
        .succ_opt()?
        .and_hms_opt(0, 0, 0)?
        .and_local_timezone(chrono::Local)
        .single()
        .map(|dt| dt.timestamp_millis().max(0) as u64)
}

/// Local calendar date of an epoch-ms timestamp, `YYYY-MM-DD`.
pub fn local_ymd(ms: u64) -> String {
    chrono::Local::now()
        .timezone()
        .timestamp_millis_opt(ms as i64)
        .single()
        .map(|d| d.format("%Y-%m-%d").to_string())
        .unwrap_or_default()
}

/// Local calendar month of an epoch-ms timestamp, `YYYY-MM`.
pub fn local_ym(ms: u64) -> String {
    chrono::Local::now()
        .timezone()
        .timestamp_millis_opt(ms as i64)
        .single()
        .map(|d| d.format("%Y-%m").to_string())
        .unwrap_or_default()
}

/// UTC calendar month of an epoch-ms timestamp, `YYYY-MM`. The Mistral
/// Console reports usage in UTC.
pub fn utc_ym(ms: u64) -> String {
    chrono::Utc
        .timestamp_millis_opt(ms as i64)
        .single()
        .map(|d| d.format("%Y-%m").to_string())
        .unwrap_or_default()
}

/// Local date and time of an epoch-ms timestamp.
pub fn local_time(ms: u64) -> String {
    chrono::Local::now()
        .timezone()
        .timestamp_millis_opt(ms as i64)
        .single()
        .map(|d| d.format("%Y-%m-%d %H:%M:%S").to_string())
        .unwrap_or_default()
}

/// Parse a timestamp for `calibrate add --at`. Accepts:
/// - RFC3339 with an explicit offset (`2026-09-28T09:36:00Z`,
///   `2026-09-28T11:36:00+02:00`) — used as-is.
/// - A naive local datetime (`2026-09-28T09:36:00` or
///   `2026-09-28 09:36:00`) — interpreted in the machine's local
///   timezone, then converted to UTC.
/// Returns epoch milliseconds.
pub fn parse_at(s: &str) -> Option<u64> {
    // RFC3339 with offset: respect it.
    if let Ok(dt) = chrono::DateTime::parse_from_rfc3339(s) {
        return Some(dt.timestamp_millis().max(0) as u64);
    }
    // Naive local datetime: try the two common shapes.
    for fmt in ["%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S"] {
        if let Ok(naive) = chrono::NaiveDateTime::parse_from_str(s, fmt) {
            return naive
                .and_local_timezone(chrono::Local)
                .single()
                .map(|dt| dt.timestamp_millis().max(0) as u64);
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::NaiveDate;

    fn start_of(day: &str) -> u64 {
        let d = NaiveDate::parse_from_str(day, "%Y-%m-%d").unwrap();
        d.and_hms_opt(0, 0, 0)
            .unwrap()
            .and_local_timezone(chrono::Local)
            .single()
            .unwrap()
            .timestamp_millis() as u64
    }

    #[test]
    fn date_bounds() {
        assert_eq!(parse_local_date_start("2026-09-28"), Some(start_of("2026-09-28")));
        // End is exclusive: first ms of the next day.
        assert_eq!(parse_local_date_end("2026-09-28"), Some(start_of("2026-09-29")));
        assert_eq!(parse_local_date_start("not-a-date"), None);
        assert_eq!(parse_local_date_end("2026-02-30"), None); // invalid day
        // chrono's date range extends past year 9999, so this still resolves.
        let far_end = parse_local_date_end("9999-12-31");
        assert!(far_end.is_some());
        assert!(far_end.unwrap() > parse_local_date_end("9999-12-30").unwrap());
    }

    #[test]
    fn ymd_round_trip() {
        let ms = start_of("2026-09-28");
        assert_eq!(local_ymd(ms), "2026-09-28");
        assert_eq!(local_ymd(ms + 86_400_000 - 1), "2026-09-28");
        assert_eq!(local_time(ms), "2026-09-28 00:00:00");
    }

    #[test]
    fn parse_at_accepts_rfc3339_and_naive_local() {
        // RFC3339 with Z: exact UTC instant.
        let utc = parse_at("2026-09-28T09:36:00Z").unwrap();
        assert_eq!(utc, 1790588160000);

        // RFC3339 with offset: same instant expressed differently.
        let offset = parse_at("2026-09-28T11:36:00+02:00").unwrap();
        assert_eq!(offset, utc);

        // Naive local datetime: interpreted in local tz, must round-trip
        // through local_time back to the same wall clock.
        let naive = parse_at("2026-09-28T09:36:00").unwrap();
        assert_eq!(local_time(naive), "2026-09-28 09:36:00");
        // Space separator also accepted.
        let naive_sp = parse_at("2026-09-28 09:36:00").unwrap();
        assert_eq!(naive_sp, naive);

        // Garbage is rejected.
        assert!(parse_at("not-a-date").is_none());
        assert!(parse_at("2026-13-45T99:99:99").is_none());
    }
}
