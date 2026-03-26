use serde::Deserialize;

#[derive(Debug, Deserialize, Clone)]
pub struct AppConfig {
    pub api_host: String,
    pub ws_host: String,
    pub meeting_link_name: String,
    pub meeting_link_password: String,
    pub http_host: String,
}

pub fn load_test_config(path: &str) -> anyhow::Result<AppConfig> {
    tracing::info!("Loading config from: {}", path);
    let content = std::fs::read_to_string(path)?;
    Ok(toml::from_str(&content)?)
}
