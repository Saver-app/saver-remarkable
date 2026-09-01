use anyhow::{Context, Result};
use serde_json::{json, Value};

use crate::api::SaverClient;
use crate::backend::local_time_zone;
use crate::config::Config;

pub fn run(command: &str, payload: Option<&str>) -> Result<()> {
    let response = match command {
        "--capture-config" => capture_config(),
        "--capture-api" => capture_api(payload.context("expected a JSON request payload")?),
        _ => anyhow::bail!("unknown capture command: {command}"),
    }
    .unwrap_or_else(|err| json!({ "error": err.to_string() }));

    println!("{response}");
    Ok(())
}

fn capture_config() -> Result<Value> {
    let config = Config::load()?;
    Ok(json!({
        "hasToken": config.device_token.is_some(),
        "confirmNotebookTodos": config.confirm_notebook_todos(),
        "notebookDefaultSpaceId": config.notebook_default_space_id,
        "notebookDefaultSpaceName": config.notebook_default_space_name,
        "notebookDefaultListId": config.notebook_default_list_id,
        "notebookDefaultListName": config.notebook_default_list_name,
        "timeZone": local_time_zone(),
    }))
}

fn capture_api(payload: &str) -> Result<Value> {
    let config = Config::load()?;
    let request = serde_json::from_str(payload).context("parsing capture request")?;
    let token = config.require_device_token()?;
    SaverClient::new(config.api_base_url(), token).call(request)
}
