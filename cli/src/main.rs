use clap::{Parser, Subcommand};
use chrono::TimeZone;
use std::path::PathBuf;
use vibe_god::aggregate::{Row, SessionRow};
use vibe_god::prices::VibeConfig;
use vibe_god::{collect_all, default_vibe_home, Totals};

#[derive(Parser)]
#[command(
    name = "vibe-god",
    about = "Track Mistral Vibe CLI token usage and estimated cost from local session journals",
    version
)]
struct Cli {
    /// Vibe home directory (default: $VIBE_HOME or ~/.vibe).
    #[arg(long, global = true)]
    vibe_home: Option<PathBuf>,

    /// Model alias or canonical name used for cost estimation (default: config active_model).
    #[arg(long, global = true)]
    model: Option<String>,

    /// Output JSON instead of text tables.
    #[arg(long, global = true)]
    json: bool,

    /// Only count events from this local date (YYYY-MM-DD).
    #[arg(long, global = true)]
    since: Option<String>,

    /// Only count events until this local date, inclusive (YYYY-MM-DD).
    #[arg(long, global = true)]
    until: Option<String>,

    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Global totals plus a per-day overview.
    Summary,
    /// Totals for today only.
    Today,
    /// Per-day breakdown.
    Daily {
        /// Number of recent days to show (default: all).
        #[arg(long)]
        days: Option<usize>,
    },
    /// Per-project breakdown.
    Projects,
    /// Per-session breakdown.
    Sessions,
    /// Raw usage events.
    Events,
    /// Re-scan every N seconds and print a summary line on change.
    Watch {
        /// Polling interval in seconds (default: 10).
        #[arg(long, default_value_t = 10)]
        interval: u64,
    },
}

fn main() {
    let cli = Cli::parse();
    let vibe_home = cli
        .vibe_home
        .clone()
        .unwrap_or_else(default_vibe_home);
    let config = VibeConfig::load(&vibe_home);
    let price = config.resolve(cli.model.as_deref()).cloned();

    let since_ms = cli.since.as_deref().and_then(parse_local_date_start);
    let until_ms = cli.until.as_deref().and_then(parse_local_date_end);

    let render = |json: bool| {
        let mut sessions = collect_all(&vibe_home);
        for s in &mut sessions {
            s.events.retain(|e| {
                since_ms.map_or(true, |t| e.timestamp_ms >= t)
                    && until_ms.map_or(true, |t| e.timestamp_ms < t)
            });
        }
        sessions.retain(|s| !s.events.is_empty());

        let price_of = |t: &Totals| -> Option<f64> {
            price.as_ref()
                .and_then(|p| p.cost_usd(t.input_tokens, t.output_tokens, t.cached_input_tokens))
        };
        (sessions, price_of, json)
    };

    match cli.command {
        Command::Summary => {
            let (sessions, price_of, json) = render(cli.json);
            let mut grand = Totals::default();
            let mut sessions_count = 0u64;
            for s in &sessions {
                sessions_count += 1;
                grand.add(&s.totals());
            }
            grand.cost_usd = price_of(&grand);
            if json {
                let daily = priced(vibe_god::aggregate_daily(&sessions), &price_of);
                println!(
                    "{}",
                    serde_json::json!({
                        "sessions": sessions_count,
                        "totals": grand,
                        "model": price.as_ref().map(|p| p.name.clone()),
                        "daily": daily,
                    })
                );
            } else {
                let model = price.as_ref().map(|p| p.name.clone()).unwrap_or_default();
                println!("Vibe usage — {} sessions (model: {})", sessions_count, if model.is_empty() { "n/a" } else { &model });
                print_totals(&grand);
                println!("\nPer day:");
                for row in vibe_god::aggregate_daily(&sessions) {
                    print_row(&row, &price_of);
                }
            }
        }
        Command::Today => {
            let today = chrono::Local::now().format("%Y-%m-%d").to_string();
            let mut sessions = collect_all(&vibe_home);
            for s in &mut sessions {
                s.events.retain(|e| local_ymd(e.timestamp_ms) == today);
            }
            sessions.retain(|s| !s.events.is_empty());
            let mut grand = Totals::default();
            for s in &sessions {
                grand.add(&s.totals());
            }
            grand.cost_usd = price
                .as_ref()
                .and_then(|p| p.cost_usd(grand.input_tokens, grand.output_tokens, grand.cached_input_tokens));
            if cli.json {
                println!("{}", serde_json::json!({"date": today, "totals": grand}));
            } else {
                println!("Vibe usage — {today}");
                print_totals(&grand);
            }
        }
        Command::Daily { days } => {
            let (sessions, price_of, json) = render(cli.json);
            let mut daily = priced(vibe_god::aggregate_daily(&sessions), &price_of);
            if let Some(n) = days {
                let len = daily.len();
                daily = daily.into_iter().skip(len.saturating_sub(n)).collect();
            }
            if json {
                println!("{}", serde_json::to_string_pretty(&daily).unwrap());
            } else {
                println!("day             sessions  requests     input   cached    output     total      cost");
                for row in &daily {
                    print_row(row, &price_of);
                }
            }
        }
        Command::Projects => {
            let (sessions, price_of, json) = render(cli.json);
            let rows = priced(vibe_god::aggregate_by_project(&sessions), &price_of);
            if json {
                println!("{}", serde_json::to_string_pretty(&rows).unwrap());
            } else {
                println!("project         sessions  requests     input   cached    output     total      cost");
                for row in &rows {
                    print_row(row, &price_of);
                }
            }
        }
        Command::Sessions => {
            let (sessions, price_of, json) = render(cli.json);
            let mut rows: Vec<SessionRow> = vibe_god::aggregate_by_session(&sessions);
            for r in &mut rows {
                r.totals.cost_usd = price_of(&r.totals);
            }
            if json {
                println!("{}", serde_json::to_string_pretty(&rows).unwrap());
            } else {
                println!("session   project             requests     input   cached    output     total      cost");
                for r in &rows {
                    let name = if r.subagent { format!("{}*{}", r.short_id, "") } else { r.short_id.clone() };
                    println!(
                        "{:<9} {:<18} {:>8} {:>9} {:>8} {:>8} {:>9} {:>10}",
                        name,
                        r.project,
                        r.totals.requests,
                        r.totals.input_tokens,
                        r.totals.cached_input_tokens,
                        r.totals.output_tokens,
                        r.totals.total_tokens,
                        cost_str(r.totals.cost_usd),
                    );
                }
            }
        }
        Command::Events => {
            let (sessions, _, json) = render(cli.json);
            let mut events: Vec<&vibe_god::UsageEvent> = sessions.iter().flat_map(|s| s.events.iter()).collect();
            events.sort_by_key(|e| e.timestamp_ms);
            if json {
                let owned: Vec<vibe_god::UsageEvent> = events.into_iter().cloned().collect();
                println!("{}", serde_json::to_string_pretty(&owned).unwrap());
            } else {
                for e in events {
                    println!(
                        "{} {} req={:>9} in={:>7} out={:>6} {}",
                        local_time(e.timestamp_ms),
                        &e.session_id[..8],
                        e.total_tokens,
                        e.input_tokens,
                        e.output_tokens,
                        e.finish_reason,
                    );
                }
            }
        }
        Command::Watch { interval } => {
            let mut last = None;
            loop {
                let (sessions, price_of, _) = render(false);
                let mut grand = Totals::default();
                for s in &sessions {
                    grand.add(&s.totals());
                }
                grand.cost_usd = price_of(&grand);
                if last.as_ref() != Some(&grand) {
                    println!(
                        "{} requests={:<5} in={:<9} cached={:<9} out={:<8} total={:<9} cost={}",
                        chrono::Local::now().format("%H:%M:%S"),
                        grand.requests,
                        grand.input_tokens,
                        grand.cached_input_tokens,
                        grand.output_tokens,
                        grand.total_tokens,
                        cost_str(grand.cost_usd),
                    );
                    last = Some(grand);
                }
                std::thread::sleep(std::time::Duration::from_secs(interval.max(1)));
            }
        }
    }
}

fn priced(mut rows: Vec<Row>, price_of: &impl Fn(&Totals) -> Option<f64>) -> Vec<Row> {
    for r in &mut rows {
        r.totals.cost_usd = price_of(&r.totals);
    }
    rows
}

fn print_totals(t: &Totals) {
    println!(
        "requests={:<6} input={:<10} cached={:<10} output={:<9} total={:<10} cost={}",
        t.requests,
        t.input_tokens,
        t.cached_input_tokens,
        t.output_tokens,
        t.total_tokens,
        cost_str(t.cost_usd),
    );
}

fn print_row(row: &Row, price_of: &impl Fn(&Totals) -> Option<f64>) {
    let cost = price_of(&row.totals);
    println!(
        "{:<14} {:<8} {:>8} {:>9} {:>8} {:>8} {:>9} {:>10}",
        row.key,
        row.sessions,
        row.totals.requests,
        row.totals.input_tokens,
        row.totals.cached_input_tokens,
        row.totals.output_tokens,
        row.totals.total_tokens,
        cost_str(cost),
    );
}

fn cost_str(cost: Option<f64>) -> String {
    cost.map(|c| format!("${c:.4}")).unwrap_or_else(|| "-".to_string())
}

fn parse_local_date_start(s: &str) -> Option<u64> {
    chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d")
        .ok()?
        .and_hms_opt(0, 0, 0)?
        .and_local_timezone(chrono::Local)
        .single()
        .map(|dt| dt.timestamp_millis().max(0) as u64)
}

fn parse_local_date_end(s: &str) -> Option<u64> {
    chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d")
        .ok()?
        .succ_opt()?
        .and_hms_opt(0, 0, 0)?
        .and_local_timezone(chrono::Local)
        .single()
        .map(|dt| dt.timestamp_millis().max(0) as u64)
}

fn local_ymd(ms: u64) -> String {
    chrono::Local::now()
        .timezone()
        .timestamp_millis_opt(ms as i64)
        .single()
        .map(|d| d.format("%Y-%m-%d").to_string())
        .unwrap_or_default()
}

fn local_time(ms: u64) -> String {
    chrono::Local::now()
        .timezone()
        .timestamp_millis_opt(ms as i64)
        .single()
        .map(|d| d.format("%Y-%m-%d %H:%M:%S").to_string())
        .unwrap_or_default()
}
