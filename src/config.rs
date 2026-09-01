use std::path::PathBuf;

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

const DEFAULT_API_BASE_URL: &str = "https://api.saver-app.com/remarkable";

const PAIRING_PATH: &str = "/pair";

const PAIRING_FUNCTION_NAME: &str = "remarkablePairing";
const API_FUNCTION_NAME: &str = "remarkableApi";

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct Config {
    pub device_token: Option<String>,
    pub api_base_url: Option<String>,
    pub pairing_url: Option<String>,
    pub confirm_notebook_todos: Option<bool>,

    pub notebook_default_space_id: Option<String>,
    pub notebook_default_space_name: Option<String>,
    pub notebook_default_list_id: Option<String>,
    pub notebook_default_list_name: Option<String>,

    pub show_in_sidebar: Option<bool>,
}

impl Config {
    pub fn config_path() -> Result<PathBuf> {
        let dir = dirs::config_dir()
            .context("could not determine the platform config directory")?
            .join("saver-remarkable");
        Ok(dir.join("config.toml"))
    }

    pub fn load() -> Result<Self> {
        let path = Self::config_path()?;
        let mut config = if path.exists() {
            let contents = std::fs::read_to_string(&path)
                .with_context(|| format!("reading {}", path.display()))?;
            toml::from_str(&contents).with_context(|| format!("parsing {}", path.display()))?
        } else {
            Self::default()
        };

        if let Ok(token) = std::env::var("SAVER_DEVICE_TOKEN") {
            config.device_token = Some(token);
        }
        if let Ok(url) = std::env::var("SAVER_API_BASE_URL") {
            config.api_base_url = Some(url);
        }
        if let Ok(url) = std::env::var("SAVER_PAIRING_URL") {
            config.pairing_url = Some(url);
        }

        Ok(config)
    }

    pub fn save(&self) -> Result<()> {
        let path = Self::config_path()?;
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)
                .with_context(|| format!("creating {}", parent.display()))?;
        }
        let contents = toml::to_string_pretty(self)?;
        std::fs::write(&path, contents).with_context(|| format!("writing {}", path.display()))?;

        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600))
                .with_context(|| format!("restricting permissions on {}", path.display()))?;
        }
        Ok(())
    }

    pub fn api_base_url(&self) -> &str {
        self.api_base_url.as_deref().unwrap_or(DEFAULT_API_BASE_URL)
    }

    pub fn pairing_url(&self) -> String {
        if let Some(url) = self.pairing_url.as_deref() {
            return url.to_string();
        }
        let api = self.api_base_url().trim_end_matches('/');
        match api.strip_suffix(API_FUNCTION_NAME) {
            Some(prefix) => format!("{prefix}{PAIRING_FUNCTION_NAME}"),
            None => format!("{api}{PAIRING_PATH}"),
        }
    }

    /// The default list lives inside the default space, so moving the space
    /// leaves it dangling.
    pub fn set_notebook_default_space(&mut self, id: String, name: Option<String>) {
        if self.notebook_default_space_id.as_deref() != Some(id.as_str()) {
            self.notebook_default_list_id = None;
            self.notebook_default_list_name = None;
        }
        self.notebook_default_space_id = Some(id);
        self.notebook_default_space_name = name;
    }

    pub fn confirm_notebook_todos(&self) -> bool {
        self.confirm_notebook_todos.unwrap_or(true)
    }

    pub fn show_in_sidebar(&self) -> bool {
        self.show_in_sidebar.unwrap_or(true)
    }

    pub fn require_device_token(&self) -> Result<&str> {
        self.device_token
            .as_deref()
            .context("this tablet is not linked to a Saver account yet")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn with_api(url: Option<&str>) -> Config {
        Config {
            api_base_url: url.map(str::to_string),
            ..Config::default()
        }
    }

    #[test]
    fn default_pairing_url_hangs_off_the_hosting_base() {
        assert_eq!(
            with_api(None).pairing_url(),
            "https://api.saver-app.com/remarkable/pair"
        );
    }

    #[test]
    fn trailing_slash_does_not_double_up() {
        assert_eq!(
            with_api(Some("https://api.saver-app.com/remarkable/")).pairing_url(),
            "https://api.saver-app.com/remarkable/pair"
        );
    }

    fn with_default_list() -> Config {
        Config {
            notebook_default_space_id: Some("space-a".to_string()),
            notebook_default_space_name: Some("Space A".to_string()),
            notebook_default_list_id: Some("list-in-a".to_string()),
            notebook_default_list_name: Some("Groceries".to_string()),
            ..Config::default()
        }
    }

    #[test]
    fn a_new_default_space_drops_the_old_default_list() {
        let mut config = with_default_list();
        config.set_notebook_default_space("space-b".to_string(), Some("Space B".to_string()));
        assert_eq!(config.notebook_default_list_id, None);
        assert_eq!(config.notebook_default_list_name, None);
    }

    #[test]
    fn reselecting_the_same_default_space_keeps_the_list() {
        let mut config = with_default_list();
        config.set_notebook_default_space("space-a".to_string(), Some("Space A".to_string()));
        assert_eq!(
            config.notebook_default_list_id.as_deref(),
            Some("list-in-a")
        );
    }

    #[test]
    fn explicit_override_wins() {
        let config = Config {
            pairing_url: Some("https://example.test/pairing".to_string()),
            ..with_api(Some("https://api.saver-app.com/remarkable"))
        };
        assert_eq!(config.pairing_url(), "https://example.test/pairing");
    }
}
