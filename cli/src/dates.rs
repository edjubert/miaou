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
}
