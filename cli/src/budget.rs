//! Monthly budget: thresholds deduced from the plan type (hardcoded
//! defaults), overridable from a config file, with optional PAYG overage.
//!
//! Config file (TOML), default `~/.config/vibe-god-cli/config.toml`:
//!
//! ```toml
//! [budget]
//! # Plan envelope for the month, USD of API-equivalent usage.
//! monthly_usd = 255.0
//! # Extra allowance consumed only when overage is allowed (PAYG credits).
//! overage_usd = 50.0
//! # Whether usage beyond the envelope is permitted at all.
//! overage_allowed = true
//! # Optional token ceiling (when cost estimation is not available).
//! monthly_tokens = 50_000_000
//! ```
//!
//! The hardcoded plan defaults are observations of what accounts report
//! (Pro/INDIVIDUAL: ~$255/month of Vibe usage), not official published
//! limits, and the config file always wins.

use crate::plan::PlanInfo;
use std::path::Path;

/// Budget thresholds. All fields optional; `None` disables that check.
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
pub struct Budget {
    /// Plan envelope for one month, USD of API-equivalent usage.
    pub monthly_usd: Option<f64>,
    /// Extra PAYG allowance, only consumed when `overage_allowed` is true.
    pub overage_usd: Option<f64>,
    /// Whether usage beyond the envelope is permitted (PAYG).
    pub overage_allowed: bool,
    /// Optional token ceiling for the month.
    pub monthly_tokens: Option<u64>,
}

impl Budget {
    /// The effective USD ceiling: envelope plus overage when allowed.
    pub fn effective_usd(&self) -> Option<f64> {
        self.monthly_usd.map(|m| {
            if self.overage_allowed {
                m + self.overage_usd.unwrap_or(0.0)
            } else {
                m
            }
        })
    }

    pub fn from_toml_str(raw: &str) -> Budget {
        let mut b = Budget::default();
        let Ok(value) = raw.parse::<toml::Value>() else {
            return b;
        };
        let Some(section) = value.get("budget") else {
            return b;
        };
        b.monthly_usd = section.get("monthly_usd").and_then(|v| v.as_float());
        b.overage_usd = section.get("overage_usd").and_then(|v| v.as_float());
        b.overage_allowed = section
            .get("overage_allowed")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        b.monthly_tokens = section.get("monthly_tokens").and_then(|v| v.as_integer()).map(|v| v.max(0) as u64);
        b
    }

    /// Load from a config file; missing or unreadable file gives defaults.
    pub fn load(path: &Path) -> Budget {
        Self::from_toml_str(&std::fs::read_to_string(path).unwrap_or_default())
    }

    /// Hardcoded defaults deduced from the plan type/name.
    /// Observed values, not officially published limits.
    pub fn defaults_for_plan(plan: &PlanInfo) -> Option<Budget> {
        if plan.plan_type.as_deref() == Some("chat")
            && plan.plan_name.as_deref().is_some_and(|n| n.eq_ignore_ascii_case("individual"))
        {
            // Mistral Pro (INDIVIDUAL): observed ~$255/month of Vibe usage.
            Some(Budget {
                monthly_usd: Some(255.0),
                overage_usd: None,
                overage_allowed: true,
                monthly_tokens: None,
            })
        } else {
            None
        }
    }
}

/// Month-to-date usage evaluated against a budget.
#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct BudgetStatus {
    pub month: String,
    pub used_usd: Option<f64>,
    pub used_tokens: u64,
    pub used_requests: u64,
    pub budget: Budget,
}

impl BudgetStatus {
    pub fn evaluate(month: &str, used_usd: Option<f64>, used_tokens: u64, used_requests: u64, budget: Budget) -> Self {
        Self { month: month.to_owned(), used_usd, used_tokens, used_requests, budget }
    }

    /// Used / effective ceiling, in [0, +inf); `None` when either side is unknown.
    pub fn pct_usd(&self) -> Option<f64> {
        Some(self.used_usd? / self.budget.effective_usd()?)
    }

    pub fn remaining_usd(&self) -> Option<f64> {
        Some(self.budget.effective_usd()? - self.used_usd?)
    }

    /// Usage beyond the monthly envelope (inside the overage allowance).
    pub fn in_overage_usd(&self) -> Option<f64> {
        let over = self.used_usd? - self.budget.monthly_usd?;
        (self.budget.overage_allowed && over > 0.0).then_some(over)
    }

    /// Usage beyond the effective (envelope + allowed overage) ceiling.
    pub fn over_limit_usd(&self) -> Option<f64> {
        let over = self.used_usd? - self.budget.effective_usd()?;
        (over > 0.0).then_some(over)
    }

    pub fn pct_tokens(&self) -> Option<f64> {
        Some(self.used_tokens as f64 / self.budget.monthly_tokens? as f64)
    }

    pub fn over_limit_tokens(&self) -> Option<u64> {
        self.budget
            .monthly_tokens
            .filter(|t| self.used_tokens > *t)
            .map(|t| self.used_tokens - t)
    }

    /// Over either ceiling, considering the cheapest available metric.
    pub fn over(&self) -> bool {
        self.over_limit_usd().unwrap_or(0.0) > 0.0 || self.over_limit_tokens().unwrap_or(0) > 0
    }
}

/// Default config path: `$XDG_CONFIG_HOME/vibe-god-cli/config.toml`,
/// else `~/.config/vibe-god-cli/config.toml`.
pub fn default_config_path() -> std::path::PathBuf {
    if let Some(xdg) = std::env::var_os("XDG_CONFIG_HOME").filter(|v| !v.is_empty()) {
        return std::path::Path::new(&xdg).join("vibe-god-cli").join("config.toml");
    }
    let home = std::env::var_os("HOME").unwrap_or_default();
    std::path::Path::new(&home).join(".config").join("vibe-god-cli").join("config.toml")
}

/// Currency symbol for cost display, from `[display] currency` in the
/// tracker config ("EUR" -> "€", "USD" -> "$", default "$"). The symbol is
/// cosmetic: prices and envelope must share whatever currency the
/// calibration observations were recorded in.
pub fn currency_symbol(config_path: &Path) -> String {
    let raw = std::fs::read_to_string(config_path).unwrap_or_default();
    let Ok(value) = raw.parse::<toml::Value>() else {
        return "$".into();
    };
    match value
        .get("display")
        .and_then(|d| d.get("currency"))
        .and_then(|c| c.as_str())
    {
        Some("EUR") | Some("€") => "€".into(),
        Some("USD") | Some("$") | None => "$".into(),
        Some(other) => other.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plan_defaults() {
        let pro = PlanInfo {
            plan_type: Some("chat".into()),
            plan_name: Some("INDIVIDUAL".into()),
            ..Default::default()
        };
        let b = Budget::defaults_for_plan(&pro).expect("pro plan has defaults");
        assert_eq!(b.monthly_usd, Some(255.0));
        assert!(b.overage_allowed);
        assert_eq!(b.effective_usd(), Some(255.0));

        let api = PlanInfo { plan_type: Some("api".into()), ..Default::default() };
        assert!(Budget::defaults_for_plan(&api).is_none());

        let team = PlanInfo {
            plan_type: Some("chat".into()),
            plan_name: Some("TEAM".into()),
            ..Default::default()
        };
        assert!(Budget::defaults_for_plan(&team).is_none());
    }

    #[test]
    fn parses_config_file() {
        let raw = r#"
[budget]
monthly_usd = 300.0
overage_usd = 50.0
overage_allowed = true
monthly_tokens = 50_000_000
"#;
        let b = Budget::from_toml_str(raw);
        assert_eq!(b.monthly_usd, Some(300.0));
        assert_eq!(b.overage_usd, Some(50.0));
        assert!(b.overage_allowed);
        assert_eq!(b.monthly_tokens, Some(50_000_000));
        assert_eq!(b.effective_usd(), Some(350.0));

        // Overage disabled: the extra allowance is not granted.
        let raw = "[budget]\nmonthly_usd = 300.0\noverage_usd = 50.0\noverage_allowed = false\n";
        let b = Budget::from_toml_str(raw);
        assert_eq!(b.effective_usd(), Some(300.0));

        // Missing file / empty / broken content -> defaults.
        assert_eq!(Budget::from_toml_str(""), Budget::default());
        assert_eq!(Budget::from_toml_str("garbage"), Budget::default());
        // No [budget] section.
        assert_eq!(Budget::from_toml_str("[other]\nx = 1\n"), Budget::default());
    }

    #[test]
    fn status_math() {
        let budget = Budget {
            monthly_usd: Some(100.0),
            overage_usd: Some(20.0),
            overage_allowed: true,
            monthly_tokens: Some(1000),
        };

        // Within envelope: percentages are relative to the effective
        // ceiling (envelope + allowed overage = 120).
        let s = BudgetStatus::evaluate("2026-09", Some(40.0), 400, 10, budget.clone());
        assert!((s.pct_usd().unwrap() - 40.0 / 120.0).abs() < 1e-12);
        assert_eq!(s.remaining_usd(), Some(80.0));
        assert_eq!(s.in_overage_usd(), None);
        assert_eq!(s.over_limit_usd(), None);
        assert!(!s.over());
        assert_eq!(s.pct_tokens(), Some(0.4));
        assert_eq!(s.over_limit_tokens(), None);

        // Inside the overage allowance.
        let s = BudgetStatus::evaluate("2026-09", Some(110.0), 1050, 20, budget.clone());
        assert_eq!(s.in_overage_usd(), Some(10.0));
        assert_eq!(s.over_limit_usd(), None); // below envelope+overage
        assert!(s.over()); // but tokens over their ceiling
        assert_eq!(s.over_limit_tokens(), Some(50));
        assert_eq!(s.pct_usd(), Some(110.0 / 120.0));

        // Beyond the effective ceiling.
        let s = BudgetStatus::evaluate("2026-09", Some(150.0), 900, 30, budget.clone());
        assert_eq!(s.over_limit_usd(), Some(30.0));
        assert!(s.over());
        assert_eq!(s.remaining_usd(), Some(-30.0));

        // Overage forbidden: envelope is the hard ceiling.
        let strict = Budget {
            monthly_usd: Some(100.0),
            overage_usd: Some(20.0),
            overage_allowed: false,
            monthly_tokens: None,
        };
        let s = BudgetStatus::evaluate("2026-09", Some(110.0), 0, 1, strict);
        assert_eq!(s.over_limit_usd(), Some(10.0));
        assert_eq!(s.in_overage_usd(), None);

        // No cost estimation: token metrics still evaluate.
        let s = BudgetStatus::evaluate("2026-09", None, 500, 5, budget);
        assert_eq!(s.pct_usd(), None);
        assert_eq!(s.remaining_usd(), None);
        assert_eq!(s.pct_tokens(), Some(0.5));
        assert!(!s.over());
    }

    #[test]
    fn default_config_path_respects_xdg() {
        // Not isolating env in unit tests: just assert the shape.
        let p = default_config_path();
        assert!(p.to_string_lossy().contains("vibe-god-cli"));
        assert!(p.to_string_lossy().ends_with("config.toml"));
    }
}
