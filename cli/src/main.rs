use clap::{Parser, Subcommand};
use std::path::PathBuf;
use vibe_god_cli::aggregate::{Row, SessionRow};
use vibe_god_cli::dates::{local_time, local_ymd, parse_local_date_end, parse_local_date_start};
use vibe_god_cli::prices::VibeConfig;
use vibe_god_cli::{collect_all, default_vibe_home, Totals};

#[derive(Subcommand)]
enum CalibrateAction {
    /// Record one observation: a Console cost at a period end (UTC).
    Add {
        /// Console period end, UTC (e.g. "2026-09-28T09:36:00Z").
        #[arg(short = 'a', long)]
        at: String,
        /// Cost shown by the Console for the month, in its display currency.
        #[arg(short = 'c', long)]
        cost: f64,
    },
    /// Show the calibration ledger.
    List,
    /// Least-squares fit of the ledger into per-million prices.
    Solve,
    /// Delete the calibration ledger.
    Clear,
}

#[derive(Parser)]
#[command(
    name = "vibe-god-cli",
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
    /// Per-month breakdown (each month starts at zero: the "reset" view).
    Monthly {
        /// Number of recent months to show (default: all).
        #[arg(long)]
        months: Option<usize>,
    },
    /// Per-project breakdown.
    Projects,
    /// Combined JSON snapshot for menu bar / bar widget consumers.
    Dashboard,
    /// Show the plan type from Vibe's local whoami cache.
    Plan,
    /// Calibrate per-token prices against Mistral Console costs.
    Calibrate {
        #[command(subcommand)]
        action: CalibrateAction,
    },
    /// Month-to-date usage against the plan budget (see README).
    Budget {
        /// Write a template config file to the config path and exit.
        #[arg(long)]
        init: bool,
        /// Config file overriding the default (~/.config/vibe-god-cli/config.toml).
        #[arg(long)]
        config: Option<PathBuf>,
    },
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
    // Die silently on SIGPIPE (e.g. `vibe-god-cli events | head`), like cat/grep.
    #[cfg(unix)]
    unsafe {
        libc::signal(libc::SIGPIPE, libc::SIG_DFL);
    }

    let cli = Cli::parse();
    let vibe_home = cli
        .vibe_home
        .clone()
        .unwrap_or_else(default_vibe_home);
    let config = VibeConfig::load(&vibe_home);
    let currency =
        vibe_god_cli::budget::currency_symbol(&vibe_god_cli::budget::default_config_path());
    let price = config.resolve(cli.model.as_deref()).cloned();

    let since_ms = cli.since.as_deref().and_then(parse_local_date_start);
    let until_ms = cli.until.as_deref().and_then(parse_local_date_end);

    let render = |json: bool| {
        let mut sessions = collect_all(&vibe_home);
        for s in &mut sessions {
            s.events.retain(|e| {
                since_ms.is_none_or(|t| e.timestamp_ms >= t)
                    && until_ms.is_none_or(|t| e.timestamp_ms < t)
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
                let daily = priced(vibe_god_cli::aggregate_daily(&sessions), &price_of);
                println!(
                    "{}",
                    serde_json::json!({
                        "sessions": sessions_count,
                        "totals": grand,
                        "model": price.as_ref().map(|p| p.name.clone()),
                        "plan": vibe_god_cli::plan::read_cached(&vibe_home),
                        "daily": daily,
                    })
                );
            } else {
                let model = price.as_ref().map(|p| p.name.clone()).unwrap_or_default();
                let plan = vibe_god_cli::plan::read_cached(&vibe_home);
                println!(
                    "Vibe usage: {} sessions (model: {}, plan: {})",
                    sessions_count,
                    if model.is_empty() { "n/a" } else { &model },
                    plan.as_ref().map(|p| p.describe()).unwrap_or_else(|| "unknown".into())
                );
                print_totals(&grand, &currency);
                println!("\nPer day:");
                let daily = vibe_god_cli::aggregate_daily(&sessions);
                let w = key_width(3, &daily);
                for row in &daily {
                    print_row(row, w, &price_of, &currency);
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
                println!("Vibe usage: {today}");
                print_totals(&grand, &currency);
            }
        }
        Command::Dashboard => {
            let (sessions, price_of, _) = render(false);
            let now_ms = now_ms();
            let today = local_ymd(now_ms);
            let current_month = vibe_god_cli::dates::local_ym(now_ms);

            let mut grand = Totals::default();
            for s in &sessions {
                grand.add(&s.totals());
            }
            grand.cost_usd = price_of(&grand);

            let mut today_totals = day_totals(&sessions, &today);
            today_totals.cost_usd = price_of(&today_totals);
            let mtd = month_to_date(&sessions, &current_month);
            let used_usd = price_of(&mtd);

            let (budget, plan) = resolve_budget(
                &vibe_home,
                &vibe_god_cli::budget::default_config_path(),
            );
            let status = vibe_god_cli::budget::BudgetStatus::evaluate(
                &current_month,
                used_usd,
                mtd.total_tokens,
                mtd.requests,
                budget.clone(),
            );

            let daily = priced(vibe_god_cli::aggregate_daily(&sessions), &price_of);
            let mut monthly = priced(vibe_god_cli::aggregate_monthly(&sessions), &price_of);
            apply_current_month_floor(&mut monthly, &sessions, &current_month, &price_of);
            let projects = priced(vibe_god_cli::aggregate_by_project(&sessions), &price_of);
            let mut session_rows = vibe_god_cli::aggregate_by_session(&sessions);
            for r in &mut session_rows {
                r.totals.cost_usd = price_of(&r.totals);
            }

            println!(
                "{}",
                serde_json::json!({
                    "generated_at_ms": now_ms,
                    "currency": currency,
                    "today": today,
                    "current_month": current_month,
                    "plan": plan,
                    "totals": grand,
                    "today_totals": today_totals,
                    "month_to_date": mtd,
                    "budget_status": status,
                    "budget": budget,
                    "daily": daily,
                    "monthly": monthly,
                    "projects": projects,
                    "sessions": session_rows,
                    "active": vibe_god_cli::status::active_sessions(&vibe_home),
                })
            );
        }
        Command::Daily { days } => {
            let (sessions, price_of, json) = render(cli.json);
            let mut daily = priced(vibe_god_cli::aggregate_daily(&sessions), &price_of);
            if let Some(n) = days {
                let len = daily.len();
                daily = daily.into_iter().skip(len.saturating_sub(n)).collect();
            }
            if json {
                println!("{}", serde_json::to_string_pretty(&daily).unwrap());
            } else {
                let w = key_width(3, &daily);
                println!("{:<w$} sessions  requests     input   cached    output     total      cost", "day");
                for row in &daily {
                    print_row(row, w, &price_of, &currency);
                }
            }
        }
        Command::Monthly { months } => {
            let (sessions, price_of, json) = render(cli.json);
            let mut monthly = priced(vibe_god_cli::aggregate_monthly(&sessions), &price_of);
            apply_current_month_floor(
                &mut monthly,
                &sessions,
                &vibe_god_cli::dates::local_ym(now_ms()),
                &price_of,
            );
            if let Some(n) = months {
                let len = monthly.len();
                monthly = monthly.into_iter().skip(len.saturating_sub(n)).collect();
            }
            if json {
                println!("{}", serde_json::to_string_pretty(&monthly).unwrap());
            } else {
                let w = key_width(5, &monthly);
                println!("{:<w$} sessions  requests     input   cached    output     total      cost", "month");
                for row in &monthly {
                    print_row(row, w, &price_of, &currency);
                }
            }
        }
        Command::Budget { init, config } => {
            let config_path = config
                .clone()
                .unwrap_or_else(vibe_god_cli::budget::default_config_path);
            if init {
                if config_path.exists() {
                    eprintln!("config already exists: {}", config_path.display());
                } else {
                    let plan = vibe_god_cli::plan::read_cached(&vibe_home);
                    let template = budget_template(plan.as_ref());
                    if let Some(parent) = config_path.parent() {
                        std::fs::create_dir_all(parent).ok();
                    }
                    match std::fs::write(&config_path, &template) {
                        Ok(()) => println!("wrote {}", config_path.display()),
                        Err(e) => eprintln!("cannot write {}: {e}", config_path.display()),
                    }
                }
                return;
            }

            // Budget source: config file wins, then plan defaults.
            let current_month = vibe_god_cli::dates::local_ym(now_ms());
            let (sessions, price_of, _) = render(false);
            let mtd = month_to_date(&sessions, &current_month);
            let used_usd = price_of(&mtd);

            let (budget, plan) = resolve_budget(
                &vibe_home,
                &config_path,
            );
            let status = vibe_god_cli::budget::BudgetStatus::evaluate(
                &current_month,
                used_usd,
                mtd.total_tokens,
                mtd.requests,
                budget.clone(),
            );

            if cli.json {
                println!(
                    "{}",
                    serde_json::json!({
                        "month": status.month,
                        "used_usd": status.used_usd,
                        "used_tokens": status.used_tokens,
                        "used_requests": status.used_requests,
                        "budget": budget,
                        "effective_usd": budget.effective_usd(),
                        "remaining_usd": status.remaining_usd(),
                        "in_overage_usd": status.in_overage_usd(),
                        "over_limit_usd": status.over_limit_usd(),
                        "over": status.over(),
                    })
                );
            } else if budget.monthly_usd.is_none() && budget.monthly_tokens.is_none() {
                println!(
                    "no budget configured: create one with `vibe-god-cli budget --init` ({})",
                    config_path.display()
                );
            } else {
                println!("Month {} - plan: {}", status.month, plan.as_ref().map(|p| p.describe()).unwrap_or_else(|| "unknown".into()));
                println!(
                    "usage: {} requests, {} tokens",
                    status.used_requests, status.used_tokens
                );
                if budget.monthly_usd.is_some() {
                    match (status.used_usd, budget.effective_usd()) {
                        (Some(used), Some(eff)) => {
                            println!(
                                "cost:   {used:.2} {currency} / {eff:.2} {currency} ({:.1}%)",
                                status.pct_usd().unwrap_or(0.0) * 100.0
                            );
                            if let Some(over) = status.in_overage_usd() {
                                println!("  in overage (PAYG): {over:.2} {currency} beyond the envelope");
                            }
                            if let Some(over) = status.over_limit_usd() {
                                println!("  OVER by {over:.2} {currency}");
                            } else if let Some(remaining) = status.remaining_usd() {
                                println!("  remaining: {remaining:.2} {currency}");
                            }
                        }
                        _ => {
                            println!(
                                "cost:   n/a: add input_price/output_price to the model entry in {}",
                                vibe_home.join("config.toml").display()
                            );
                        }
                    }
                } else {
                    println!("cost:   n/a (no price configured for the model)");
                }
                if let Some(token_ceiling) = budget.monthly_tokens {
                    println!(
                        "tokens: {} / {token_ceiling} ({:.1}%){}",
                        status.used_tokens,
                        status.pct_tokens().unwrap_or(0.0) * 100.0,
                        status.over_limit_tokens().map(|o| format!(" (OVER by {o})")).unwrap_or_default()
                    );
                }
                println!(
                    "overage: {}",
                    if budget.overage_allowed { "allowed (PAYG)" } else { "not allowed" }
                );
            }
        }
        Command::Calibrate { action } => {
            let ledger = vibe_god_cli::calibrate::ledger_path();
            match action {
                CalibrateAction::Add { at, cost } => {
                    let parsed = chrono::DateTime::parse_from_rfc3339(&at)
                        .map_err(|e| {
                            eprintln!("invalid --at (expect RFC3339 UTC, e.g. 2026-09-28T09:36:00Z): {e}");
                            std::process::exit(2);
                        })
                        .unwrap();
                    let at_ms = parsed.timestamp_millis().max(0) as u64;
                    let sessions = collect_all(&vibe_home);
                    let mut observation = vibe_god_cli::calibrate::month_tokens_at(&sessions, at_ms);
                    observation.cost = cost;
                    vibe_god_cli::calibrate::append_ledger(&ledger, &observation).unwrap();
                    println!(
                        "recorded observation at {at}: cost {cost}, {} input / {} cached / {} output tokens (UTC month {})",
                        observation.input_tokens,
                        observation.cached_input_tokens,
                        observation.output_tokens,
                        vibe_god_cli::dates::utc_ym(at_ms)
                    );
                    let count = vibe_god_cli::calibrate::load_ledger(&ledger).len();
                    if count < 4 {
                        println!("ledger has {count} observation(s); 4+ (3 deltas with varied token mixes) are needed to solve");
                    }
                }
                CalibrateAction::List => {
                    let all = vibe_god_cli::calibrate::load_ledger(&ledger);
                    if all.is_empty() {
                        println!("ledger is empty: {}", ledger.display());
                    }
                    for o in &all {
                        println!(
                            "{}  cost={:<10.4}  in={:<9} cached={:<9} out={:<7}",
                            chrono::DateTime::from_timestamp((o.at_ms / 1000) as i64, 0)
                                .map(|d| d.to_rfc3339())
                                .unwrap_or_default(),
                            o.cost,
                            o.input_tokens,
                            o.cached_input_tokens,
                            o.output_tokens
                        );
                    }
                }
                CalibrateAction::Solve => {
                    let all = vibe_god_cli::calibrate::load_ledger(&ledger);
                    match vibe_god_cli::calibrate::solve(&all) {
                        Some(s) => {
                            println!("fitted over {} observations (prices in observation currency, per million tokens):", all.len());
                            println!("input_price         = {:.4}", s.input_price);
                            println!("cached_input_price  = {:.4}", s.cached_input_price);
                            println!("output_price        = {:.4}", s.output_price);
                            println!("rms error            = {:.6}", s.rms);
                            for (i, r) in s.residuals.iter().enumerate() {
                                println!("  obs {i}: residual {r:+.6}");
                            }
                            println!("\nPaste into the [[models]] entry in ~/.vibe/config.toml.");
                        }
                        None => {
                            if all.len() < 4 {
                                eprintln!("need at least 4 observations (3 deltas) to solve, have {}", all.len());
                            } else {
                                eprintln!("observations are degenerate: token mixes too similar to separate input/cached/output prices");
                            }
                        }
                    }
                }
                CalibrateAction::Clear => {
                    match std::fs::remove_file(&ledger) {
                        Ok(()) => println!("deleted {}", ledger.display()),
                        Err(_) => println!("no ledger at {}", ledger.display()),
                    }
                }
            }
        }
        Command::Plan => {
            match vibe_god_cli::plan::read_cached(&vibe_home) {
                Some(plan) => {
                    if cli.json {
                        println!("{}", serde_json::to_string_pretty(&plan).unwrap());
                    } else {
                        println!("plan: {}", plan.describe());
                        println!("plan_type: {}", plan.plan_type.as_deref().unwrap_or("?"));
                        println!("plan_name: {}", plan.plan_name.as_deref().unwrap_or("?"));
                        println!(
                            "organization_kind: {}",
                            plan.organization_kind.as_deref().unwrap_or("?")
                        );
                    }
                }
                None => {
                    if cli.json {
                        println!("null");
                    } else {
                        println!("plan: unknown (no whoami cache; run /whoami in Vibe once)");
                    }
                }
            }
        }
        Command::Projects => {
            let (sessions, price_of, json) = render(cli.json);
            let rows = priced(vibe_god_cli::aggregate_by_project(&sessions), &price_of);
            if json {
                println!("{}", serde_json::to_string_pretty(&rows).unwrap());
            } else {
                let w = key_width(7, &rows);
                println!("{:<w$} sessions  requests     input   cached    output     total      cost", "project");
                for row in &rows {
                    print_row(row, w, &price_of, &currency);
                }
            }
        }
        Command::Sessions => {
            let (sessions, price_of, json) = render(cli.json);
            let mut rows: Vec<SessionRow> = vibe_god_cli::aggregate_by_session(&sessions);
            for r in &mut rows {
                r.totals.cost_usd = price_of(&r.totals);
            }
            if json {
                println!("{}", serde_json::to_string_pretty(&rows).unwrap());
            } else {
                let pw = rows
                    .iter()
                    .map(|r| r.project.len())
                    .max()
                    .unwrap_or(0)
                    .max(7);
                println!(
                    "{:<9} {:<pw$} {:>8} {:>9} {:>8} {:>8} {:>9} {:>10}",
                    "session", "project", "req", "input", "cached", "output", "total", "cost"
                );
                for r in &rows {
                    let name = if r.subagent { format!("{}*", r.short_id) } else { r.short_id.clone() };
                    println!(
                        "{:<9} {:<pw$} {:>8} {:>9} {:>8} {:>8} {:>9} {:>10}",
                        name,
                        r.project,
                        r.totals.requests,
                        r.totals.input_tokens,
                        r.totals.cached_input_tokens,
                        r.totals.output_tokens,
                        r.totals.total_tokens,
                        cost_str(r.totals.cost_usd, &currency),
                    );
                }
            }
        }
        Command::Events => {
            let (sessions, _, json) = render(cli.json);
            let mut events: Vec<&vibe_god_cli::UsageEvent> = sessions.iter().flat_map(|s| s.events.iter()).collect();
            events.sort_by_key(|e| e.timestamp_ms);
            if json {
                let owned: Vec<vibe_god_cli::UsageEvent> = events.into_iter().cloned().collect();
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
                        cost_str(grand.cost_usd, &currency),
                    );
                    last = Some(grand);
                }
                std::thread::sleep(std::time::Duration::from_secs(interval.max(1)));
            }
        }
    }
}

fn budget_template(plan: Option<&vibe_god_cli::plan::PlanInfo>) -> String {
    let defaults = plan.and_then(vibe_god_cli::budget::Budget::defaults_for_plan);
    let line = |comment: &str, key: &str, value: Option<String>| match value {
        Some(v) => format!("{key} = {v}"),
        None => format!("# {comment}\n# {key} = 0.0"),
    };
    format!(
        r#"# vibe-god-cli budget configuration.
# Values here override the hardcoded plan defaults.
# Cost estimation also needs model prices in Vibe's config.toml
# ([[models]] input_price / output_price / cached_input_price).

[budget]
# Plan envelope for the month, USD of API-equivalent usage.
{monthly_usd}

# Extra allowance consumed only when overage_allowed is true (PAYG credits).
{overage_usd}

# Whether usage beyond the envelope is permitted at all.
overage_allowed = {overage_allowed}

# Optional token ceiling (used when cost estimation is not available).
# monthly_tokens = 50_000_000
"#,
        monthly_usd = line("No plan default found; set your envelope.", "monthly_usd", defaults.as_ref().and_then(|b| b.monthly_usd).map(|v| v.to_string())),
        overage_usd = line("No overage allowance by default.", "overage_usd", defaults.as_ref().and_then(|b| b.overage_usd).map(|v| v.to_string())),
        overage_allowed = defaults.map(|b| b.overage_allowed).unwrap_or(true),
    )
}

fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

/// Totals of the events in `sessions` that fall on local day `ymd`.
fn day_totals(sessions: &[vibe_god_cli::SessionUsage], ymd: &str) -> Totals {
    let mut totals = Totals::default();
    for s in sessions {
        let events: Vec<&vibe_god_cli::UsageEvent> =
            s.events.iter().filter(|e| local_ymd(e.timestamp_ms) == ymd).collect();
        totals.add(&Totals::from_events(events.into_iter()));
    }
    totals
}

/// Totals of the events in `sessions` that fall in local month `ym`.
fn month_to_date(sessions: &[vibe_god_cli::SessionUsage], ym: &str) -> Totals {
    month_to_date_floored(sessions, ym)
}

/// Overwrite the current-month row with the floored month totals, so the
/// monthly tables agree with the budget and the menu bar.
fn apply_current_month_floor(
    monthly: &mut [Row],
    sessions: &[vibe_god_cli::SessionUsage],
    ym: &str,
    price_of: &impl Fn(&Totals) -> Option<f64>,
) {
    if let Some(row) = monthly.iter_mut().find(|r| r.key == ym) {
        let mtd = month_to_date_floored(sessions, ym);
        let cost = price_of(&mtd);
        row.totals = mtd;
        row.totals.cost_usd = cost;
    }
}

fn month_to_date_floored(sessions: &[vibe_god_cli::SessionUsage], ym: &str) -> Totals {
    let ledger = vibe_god_cli::calibrate::load_ledger(
        &vibe_god_cli::calibrate::ledger_path(),
    );
    vibe_god_cli::calibrate::floored_month_totals(sessions, ym, now_ms(), &ledger)
}

/// Budget from the config file (when it declares one), else plan defaults.
/// Returns the plan for display purposes.
fn resolve_budget(
    vibe_home: &std::path::Path,
    config_path: &std::path::Path,
) -> (vibe_god_cli::budget::Budget, Option<vibe_god_cli::plan::PlanInfo>) {
    let from_file = vibe_god_cli::budget::Budget::load(config_path);
    let plan = vibe_god_cli::plan::read_cached(vibe_home);
    let configured = from_file.monthly_usd.is_some()
        || from_file.overage_usd.is_some()
        || from_file.monthly_tokens.is_some();
    let budget = if configured {
        from_file
    } else {
        plan.as_ref()
            .and_then(vibe_god_cli::budget::Budget::defaults_for_plan)
            .unwrap_or(from_file)
    };
    (budget, plan)
}

fn priced(mut rows: Vec<Row>, price_of: &impl Fn(&Totals) -> Option<f64>) -> Vec<Row> {
    for r in &mut rows {
        r.totals.cost_usd = price_of(&r.totals);
    }
    rows
}

fn print_totals(t: &Totals, currency: &str) {
    println!(
        "requests={:<6} input={:<10} cached={:<10} output={:<9} total={:<10} cost={}",
        t.requests,
        t.input_tokens,
        t.cached_input_tokens,
        t.output_tokens,
        t.total_tokens,
        cost_str(t.cost_usd, currency),
    );
}

fn print_row(row: &Row, key_width: usize, price_of: &impl Fn(&Totals) -> Option<f64>, currency: &str) {
    let cost = price_of(&row.totals);
    println!(
        "{:<key_width$} {:<8} {:>8} {:>9} {:>8} {:>8} {:>9} {:>10}",
        row.key,
        row.sessions,
        row.totals.requests,
        row.totals.input_tokens,
        row.totals.cached_input_tokens,
        row.totals.output_tokens,
        row.totals.total_tokens,
        cost_str(cost, currency),
    );
}

/// Column width for a key: at least the header length, at most the longest key.
fn key_width(header_len: usize, rows: &[Row]) -> usize {
    rows.iter()
        .map(|r| r.key.len())
        .max()
        .unwrap_or(0)
        .max(header_len)
}

fn cost_str(cost: Option<f64>, currency: &str) -> String {
    cost.map(|c| format!("{c:.4} {currency}")).unwrap_or_else(|| "-".to_string())
}
