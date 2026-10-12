//! Price resolution from the Vibe `config.toml` model declarations.
//!
//! Vibe declares models with `input_price` / `output_price` / `cached_input_price`
//! (USD per million tokens). Journals do not record which model produced a
//! completion, so cost is an estimate attributed to a configured model
//! (`--model` alias/name, else `active_model`, else the first priced model).

use std::path::Path;

/// Mistral's published USD→EUR price ratio, observed on
/// `mistral.ai/pricing/api` (2026-10): the EUR rate card is exactly
/// USD × 0.85 on every model and token type (input / cached / output).
/// Config prices are stored in USD; multiply by this to get EUR.
pub const USD_TO_EUR: f64 = 0.85;

#[derive(Debug, Clone, Default)]
pub struct ModelPrice {
    pub name: String,
    pub alias: Option<String>,
    pub input_price: Option<f64>,
    pub output_price: Option<f64>,
    pub cached_input_price: Option<f64>,
}

impl ModelPrice {
    /// Estimation assumes `input_tokens` includes cached tokens (observed:
    /// total = input + output, cached ⊂ input), and that a missing
    /// `cached_input_price` bills cached tokens at `input_price`.
    pub fn cost_usd(
        &self,
        input_tokens: u64,
        output_tokens: u64,
        cached_input_tokens: u64,
    ) -> Option<f64> {
        let ip = self.input_price?;
        let op = self.output_price?;
        let cp = self.cached_input_price.unwrap_or(ip);
        let uncached = input_tokens.saturating_sub(cached_input_tokens);
        Some(
            (uncached as f64 * ip + cached_input_tokens as f64 * cp + output_tokens as f64 * op)
                / 1_000_000.0,
        )
    }
}

/// Parsed subset of `~/.vibe/config.toml`.
#[derive(Debug, Clone, Default)]
pub struct VibeConfig {
    pub active_model: Option<String>,
    pub models: Vec<ModelPrice>,
}

impl VibeConfig {
    pub fn load(vibe_home: &Path) -> Self {
        let path = vibe_home.join("config.toml");
        Self::parse(&std::fs::read_to_string(path).unwrap_or_default())
    }

    pub fn parse(raw: &str) -> Self {
        let mut cfg = VibeConfig::default();
        let Ok(value) = raw.parse::<toml::Value>() else {
            return cfg;
        };
        if let Some(active) = value.get("active_model").and_then(|v| v.as_str()) {
            if !active.is_empty() {
                cfg.active_model = Some(active.to_string());
            }
        }
        if let Some(models) = value.get("models").and_then(|v| v.as_array()) {
            for m in models {
                let get_f64 = |k: &str| m.get(k).and_then(|v| v.as_float());
                cfg.models.push(ModelPrice {
                    name: m.get("name").and_then(|v| v.as_str()).unwrap_or_default().to_string(),
                    alias: m.get("alias").and_then(|v| v.as_str()).map(str::to_owned),
                    input_price: get_f64("input_price"),
                    output_price: get_f64("output_price"),
                    cached_input_price: get_f64("cached_input_price"),
                });
            }
        }
        cfg
    }

    /// Resolve a model by alias first, then by canonical name.
    pub fn resolve(&self, requested: Option<&str>) -> Option<&ModelPrice> {
        let want = requested.or(self.active_model.as_deref())?;
        self.models
            .iter()
            .find(|m| m.alias.as_deref() == Some(want))
            .or_else(|| self.models.iter().find(|m| m.name == want))
    }

    /// Resolve a model by alias or canonical name only (no active_model
    /// fallback). Used for per-session pricing where the session's own
    /// model is known.
    pub fn resolve_name(&self, name: &str) -> Option<&ModelPrice> {
        self.models
            .iter()
            .find(|m| m.alias.as_deref() == Some(name))
            .or_else(|| self.models.iter().find(|m| m.name == name))
    }

    /// Cost of one session's tokens, priced at the session's own model.
    /// Falls back to `fallback` (the active/requested model) when the
    /// session's model is unknown or unpriced. Prices are in USD (the
    /// config's currency); multiply by `USD_TO_EUR` for EUR display.
    pub fn cost_for_session(
        &self,
        session_model: Option<&str>,
        input_tokens: u64,
        output_tokens: u64,
        cached_input_tokens: u64,
        fallback: Option<&ModelPrice>,
    ) -> Option<f64> {
        let price = session_model
            .and_then(|m| self.resolve_name(m))
            .or(fallback)?;
        price.cost_usd(input_tokens, output_tokens, cached_input_tokens)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_config() {
        let raw = r#"
active_model = "glm-5-3"

[[models]]
name = "zai-glm-5-3"
provider = "mistral"
alias = "glm-5-3"
input_price = 1.5
output_price = 7.5

[[models]]
name = "no-prices"
alias = "bare"
"#;
        let cfg = VibeConfig::parse(raw);
        assert_eq!(cfg.active_model.as_deref(), Some("glm-5-3"));
        assert_eq!(cfg.models.len(), 2);
        let m = cfg.resolve(None).unwrap();
        assert_eq!(m.name, "zai-glm-5-3");
        // 8619 input (cached billed at input_price), 83 output at 1.5/7.5 per M.
        let cost = m.cost_usd(8619, 83, 6656).unwrap();
        assert!((cost - 0.013551).abs() < 1e-9, "{cost}");
        // bare model has no prices -> no cost
        assert!(cfg.resolve(Some("bare")).unwrap().cost_usd(1, 1, 0).is_none());
    }

    #[test]
    fn resolve_name_matches_alias_then_name() {
        let raw = r#"
[[models]]
name = "zai-glm-5-3"
alias = "glm-5-3"
input_price = 1.4
output_price = 4.4
cached_input_price = 0.14

[[models]]
name = "mistral-small-latest"
alias = "Small 4"
input_price = 0.15
output_price = 0.6
cached_input_price = 0.015
"#;
        let cfg = VibeConfig::parse(raw);
        // By alias.
        assert_eq!(cfg.resolve_name("glm-5-3").unwrap().name, "zai-glm-5-3");
        // By canonical name.
        assert_eq!(
            cfg.resolve_name("mistral-small-latest").unwrap().alias.as_deref(),
            Some("Small 4")
        );
        // Unknown.
        assert!(cfg.resolve_name("nope").is_none());
    }

    #[test]
    fn cost_for_session_uses_session_model() {
        let raw = r#"
active_model = "Small 4"

[[models]]
name = "zai-glm-5-3"
alias = "glm-5-3"
input_price = 1.4
output_price = 4.4
cached_input_price = 0.14

[[models]]
name = "mistral-small-latest"
alias = "Small 4"
input_price = 0.15
output_price = 0.6
cached_input_price = 0.015
"#;
        let cfg = VibeConfig::parse(raw);
        let fallback = cfg.resolve(None).cloned();

        // Session on glm-5-3: 1M input (0.9M cached), 0.1M output.
        // cost = (0.1M * 1.4 + 0.9M * 0.14 + 0.1M * 4.4) / 1e6
        //      = (140000 + 126000 + 440000) / 1e6 = 0.706 USD
        let cost = cfg
            .cost_for_session(Some("glm-5-3"), 1_000_000, 100_000, 900_000, fallback.as_ref())
            .unwrap();
        assert!((cost - 0.706).abs() < 1e-9, "{cost}");

        // Session on Small 4: same tokens.
        // cost = (0.1M * 0.15 + 0.9M * 0.015 + 0.1M * 0.6) / 1e6
        //      = (15000 + 13500 + 60000) / 1e6 = 0.0885 USD
        let cost = cfg
            .cost_for_session(Some("Small 4"), 1_000_000, 100_000, 900_000, fallback.as_ref())
            .unwrap();
        assert!((cost - 0.0885).abs() < 1e-9, "{cost}");

        // Unknown session model falls back to the active model (Small 4).
        let cost = cfg
            .cost_for_session(Some("unknown-model"), 1_000_000, 100_000, 900_000, fallback.as_ref())
            .unwrap();
        assert!((cost - 0.0885).abs() < 1e-9, "{cost}");

        // No session model, no fallback -> None.
        assert!(cfg
            .cost_for_session(None, 1_000_000, 100_000, 900_000, None)
            .is_none());
    }

    #[test]
    fn usd_to_eur_constant() {
        assert!((USD_TO_EUR - 0.85).abs() < 1e-12);
    }
}
