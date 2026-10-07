//! Price resolution from the Vibe `config.toml` model declarations.
//!
//! Vibe declares models with `input_price` / `output_price` / `cached_input_price`
//! (USD per million tokens). Journals do not record which model produced a
//! completion, so cost is an estimate attributed to a configured model
//! (`--model` alias/name, else `active_model`, else the first priced model).

use std::path::Path;

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
}
