use anyhow::Result;
use serde::Deserialize;
use serde_json::json;

use crate::http::{self, Retry};
use crate::models::{HabitRequirement, ReminderSettings, Space};

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

impl SaverClient {
    pub fn new(base_url: impl Into<String>, device_token: impl Into<String>) -> Self {
        Self {
            http: http::blocking_client(),
            base_url: base_url.into(),
            device_token: device_token.into(),
        }
    }

    pub(crate) fn call(&self, body: serde_json::Value) -> Result<serde_json::Value> {
        http::send_json("Saver API error", Retry::OnColdStart, || {
            self.http
                .post(&self.base_url)
                .bearer_auth(&self.device_token)
                .json(&body)
        })
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

    pub fn update_todo(
        &self,
        space_id: &str,
        todo_id: &str,
        text: &str,
        reminder: Option<&ReminderSettings>,
        remove_reminder: bool,
    ) -> Result<()> {
        self.call(json!({
            "op": "updateTodo",
            "spaceId": space_id,
            "todoId": todo_id,
            "text": text,
            "reminder": reminder,
            "removeReminder": remove_reminder,
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
        reminder: Option<&ReminderSettings>,
        remove_reminder: bool,
    ) -> Result<()> {
        self.call(json!({
            "op": "updateBookmark",
            "spaceId": space_id,
            "bookmarkId": bookmark_id,
            "title": title,
            "url": url,
            "isList": is_list,
            "reminder": reminder,
            "removeReminder": remove_reminder,
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
