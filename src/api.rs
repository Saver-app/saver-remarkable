use std::time::Duration;

use anyhow::{bail, Context, Result};
use serde::Deserialize;
use serde_json::json;

use crate::models::{HabitRequirement, Space};

const CONNECT_TIMEOUT: Duration = Duration::from_secs(8);
const REQUEST_TIMEOUT: Duration = Duration::from_secs(15);

fn network_error_message(err: &reqwest::Error) -> String {
    if err.is_timeout() {
        "Saver took too long to respond. Check your Wi-Fi and try again.".to_string()
    } else if err.is_connect() {
        "Could not reach Saver. Check your Wi-Fi and try again.".to_string()
    } else {
        format!("Could not reach Saver: {err}")
    }
}

pub struct SaverClient {
    http: reqwest::blocking::Client,
    base_url: String,
    device_token: String,
}

#[derive(Deserialize)]
pub struct ItemsListing {
    pub spaces: Vec<Space>,
    #[serde(rename = "activeSpaceId")]
    pub active_space_id: Option<String>,
}

#[derive(Deserialize)]
struct CreateTodoResponse {
    id: String,
}

#[derive(Deserialize)]
struct ErrorResponse {
    error: String,
}

impl SaverClient {
    pub fn new(base_url: impl Into<String>, device_token: impl Into<String>) -> Self {
        Self {
            http: reqwest::blocking::Client::builder()
                .connect_timeout(CONNECT_TIMEOUT)
                .timeout(REQUEST_TIMEOUT)
                .build()
                .expect("building the Saver API HTTP client"),
            base_url: base_url.into(),
            device_token: device_token.into(),
        }
    }

    pub(crate) fn call(&self, body: serde_json::Value) -> Result<serde_json::Value> {
        let response = self
            .http
            .post(&self.base_url)
            .bearer_auth(&self.device_token)
            .json(&body)
            .send()
            .map_err(|err| anyhow::anyhow!(network_error_message(&err)))?;

        let status = response.status();
        let text = response.text().context("reading response body")?;

        if !status.is_success() {
            let message = serde_json::from_str::<ErrorResponse>(&text)
                .map(|e| e.error)
                .unwrap_or(text);
            bail!("Saver API error ({status}): {message}");
        }

        serde_json::from_str(&text).context("parsing response body")
    }

    pub fn list_items(&self) -> Result<ItemsListing> {
        let value = self.call(json!({ "op": "listItems" }))?;
        Ok(serde_json::from_value(value)?)
    }

    pub fn set_active_space(&self, space_id: &str) -> Result<()> {
        self.call(json!({
            "op": "setActiveSpace",
            "spaceId": space_id,
        }))?;
        Ok(())
    }

    pub fn set_habit_count(&self, space_id: &str, habit_id: &str, count: u32) -> Result<()> {
        self.call(json!({
            "op": "setHabitCount",
            "spaceId": space_id,
            "habitId": habit_id,
            "count": count,
        }))?;
        Ok(())
    }

    pub fn create_todo(
        &self,
        space_id: &str,
        text: &str,
        parent_id: Option<&str>,
        is_list: bool,
    ) -> Result<String> {
        let value = self.call(json!({
            "op": "createTodo",
            "spaceId": space_id,
            "text": text,
            "parentId": parent_id,
            "isList": is_list,
        }))?;
        let parsed: CreateTodoResponse = serde_json::from_value(value)?;
        Ok(parsed.id)
    }

    pub fn create_bookmark(
        &self,
        space_id: &str,
        title: &str,
        url: &str,
        is_list: bool,
        parent_id: Option<&str>,
    ) -> Result<String> {
        let value = self.call(json!({
            "op": "createBookmark",
            "spaceId": space_id,
            "title": title,
            "url": url,
            "isList": is_list,
            "parentId": parent_id,
        }))?;
        let parsed: CreateTodoResponse = serde_json::from_value(value)?;
        Ok(parsed.id)
    }

    pub fn create_habit(
        &self,
        space_id: &str,
        name: &str,
        requirement: &HabitRequirement,
    ) -> Result<String> {
        let mut body = serde_json::to_value(requirement)?;
        body["op"] = json!("createHabit");
        body["spaceId"] = json!(space_id);
        body["name"] = json!(name);
        let value = self.call(body)?;
        let parsed: CreateTodoResponse = serde_json::from_value(value)?;
        Ok(parsed.id)
    }

    pub fn update_habit(
        &self,
        space_id: &str,
        habit_id: &str,
        name: &str,
        requirement: &HabitRequirement,
    ) -> Result<()> {
        let mut body = serde_json::to_value(requirement)?;
        body["op"] = json!("updateHabit");
        body["spaceId"] = json!(space_id);
        body["habitId"] = json!(habit_id);
        body["name"] = json!(name);
        self.call(body)?;
        Ok(())
    }

    pub fn update_todo(&self, space_id: &str, todo_id: &str, text: &str) -> Result<()> {
        self.call(json!({
            "op": "updateTodo",
            "spaceId": space_id,
            "todoId": todo_id,
            "text": text,
        }))?;
        Ok(())
    }

    pub fn update_bookmark(
        &self,
        space_id: &str,
        bookmark_id: &str,
        title: &str,
        url: &str,
        is_list: bool,
    ) -> Result<()> {
        self.call(json!({
            "op": "updateBookmark",
            "spaceId": space_id,
            "bookmarkId": bookmark_id,
            "title": title,
            "url": url,
            "isList": is_list,
        }))?;
        Ok(())
    }

    pub fn set_todo_done(&self, space_id: &str, todo_id: &str, is_done: bool) -> Result<()> {
        self.call(json!({
            "op": "setTodoDone",
            "spaceId": space_id,
            "todoId": todo_id,
            "isDone": is_done,
        }))?;
        Ok(())
    }
}
