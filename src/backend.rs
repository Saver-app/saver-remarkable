use anyhow::Result;
use serde::{Deserialize, Serialize};
use serde_json::json;

use crate::api::SaverClient;
use crate::appload::{AppLoadSocket, Message, MSG_SYSTEM_NEW_COORDINATOR, MSG_SYSTEM_TERMINATE};
use crate::config::Config;
use crate::models::HabitRequirement;
use crate::pairing::{qr_matrix, PairingClient, PairingStart, PairingStatus};

pub const MSG_GET_CONFIG: u32 = 1001;
pub const MSG_SAVE_CONFIG: u32 = 1002;
pub const MSG_LIST_TODOS: u32 = 1003;
pub const MSG_CREATE_TODO: u32 = 1004;
pub const MSG_SET_TODO_DONE: u32 = 1005;
pub const MSG_START_PAIRING: u32 = 1006;
pub const MSG_POLL_PAIRING: u32 = 1007;
pub const MSG_UNLINK: u32 = 1008;
pub const MSG_SET_HABIT_COUNT: u32 = 1009;
pub const MSG_CREATE_BOOKMARK: u32 = 1010;
pub const MSG_CREATE_HABIT: u32 = 1011;
pub const MSG_UPDATE_HABIT: u32 = 1012;
pub const MSG_UPDATE_TODO: u32 = 1013;
pub const MSG_UPDATE_BOOKMARK: u32 = 1014;
pub const MSG_SET_ACTIVE_SPACE: u32 = 1015;

pub const MSG_GET_CONFIG_RESPONSE: u32 = 1101;
pub const MSG_SAVE_CONFIG_RESPONSE: u32 = 1102;
pub const MSG_LIST_TODOS_RESPONSE: u32 = 1103;
pub const MSG_CREATE_TODO_RESPONSE: u32 = 1104;
pub const MSG_SET_TODO_DONE_RESPONSE: u32 = 1105;
pub const MSG_START_PAIRING_RESPONSE: u32 = 1106;
pub const MSG_POLL_PAIRING_RESPONSE: u32 = 1107;
pub const MSG_UNLINK_RESPONSE: u32 = 1108;
pub const MSG_SET_HABIT_COUNT_RESPONSE: u32 = 1109;
pub const MSG_CREATE_BOOKMARK_RESPONSE: u32 = 1110;
pub const MSG_CREATE_HABIT_RESPONSE: u32 = 1111;
pub const MSG_UPDATE_HABIT_RESPONSE: u32 = 1112;
pub const MSG_UPDATE_TODO_RESPONSE: u32 = 1113;
pub const MSG_UPDATE_BOOKMARK_RESPONSE: u32 = 1114;
pub const MSG_SET_ACTIVE_SPACE_RESPONSE: u32 = 1115;

pub struct Backend {
    config: Config,
    pairing: Option<PairingStart>,
}

#[derive(Serialize)]
struct ConfigPayload {
    #[serde(rename = "hasToken")]
    has_token: bool,
    #[serde(rename = "apiBaseUrl")]
    api_base_url: String,
    #[serde(rename = "confirmNotebookTodos")]
    confirm_notebook_todos: bool,
    #[serde(rename = "notebookDefaultSpaceId")]
    notebook_default_space_id: Option<String>,
    #[serde(rename = "notebookDefaultSpaceName")]
    notebook_default_space_name: Option<String>,
    #[serde(rename = "notebookDefaultListId")]
    notebook_default_list_id: Option<String>,
    #[serde(rename = "notebookDefaultListName")]
    notebook_default_list_name: Option<String>,
    #[serde(rename = "showInSidebar")]
    show_in_sidebar: bool,
}

#[derive(Deserialize)]
struct SaveConfigRequest {
    #[serde(rename = "deviceToken")]
    device_token: Option<String>,
    #[serde(rename = "confirmNotebookTodos")]
    confirm_notebook_todos: Option<bool>,
    #[serde(rename = "notebookDefaultSpaceId")]
    notebook_default_space_id: Option<String>,
    #[serde(rename = "notebookDefaultSpaceName")]
    notebook_default_space_name: Option<String>,
    #[serde(rename = "clearNotebookDefaultSpace", default)]
    clear_notebook_default_space: bool,
    #[serde(rename = "notebookDefaultListId")]
    notebook_default_list_id: Option<String>,
    #[serde(rename = "notebookDefaultListName")]
    notebook_default_list_name: Option<String>,
    #[serde(rename = "clearNotebookDefaultList", default)]
    clear_notebook_default_list: bool,
    #[serde(rename = "showInSidebar")]
    show_in_sidebar: Option<bool>,
}

#[derive(Deserialize)]
struct CreateTodoRequest {
    #[serde(rename = "spaceId")]
    space_id: String,
    text: String,
    #[serde(rename = "parentId")]
    parent_id: Option<String>,
    #[serde(rename = "isList", default)]
    is_list: bool,
}

#[derive(Deserialize)]
struct CreateBookmarkRequest {
    #[serde(rename = "spaceId")]
    space_id: String,
    title: String,
    #[serde(default)]
    url: String,
    #[serde(rename = "isList", default)]
    is_list: bool,
    #[serde(rename = "parentId")]
    parent_id: Option<String>,
}

#[derive(Deserialize)]
struct CreateHabitRequest {
    #[serde(rename = "spaceId")]
    space_id: String,
    name: String,
    #[serde(flatten)]
    requirement: HabitRequirement,
}

#[derive(Deserialize)]
struct UpdateHabitRequest {
    #[serde(rename = "spaceId")]
    space_id: String,
    #[serde(rename = "habitId")]
    habit_id: String,
    name: String,
    #[serde(flatten)]
    requirement: HabitRequirement,
}

#[derive(Deserialize)]
struct SetHabitCountRequest {
    #[serde(rename = "spaceId")]
    space_id: String,
    #[serde(rename = "habitId")]
    habit_id: String,
    count: u32,
}

#[derive(Deserialize)]
struct SetActiveSpaceRequest {
    #[serde(rename = "spaceId")]
    space_id: String,
}

#[derive(Deserialize)]
struct UpdateTodoRequest {
    #[serde(rename = "spaceId")]
    space_id: String,
    #[serde(rename = "todoId")]
    todo_id: String,
    text: String,
}

#[derive(Deserialize)]
struct UpdateBookmarkRequest {
    #[serde(rename = "spaceId")]
    space_id: String,
    #[serde(rename = "bookmarkId")]
    bookmark_id: String,
    title: String,
    #[serde(default)]
    url: String,
    #[serde(rename = "isList", default)]
    is_list: bool,
}

#[derive(Deserialize)]
struct SetTodoDoneRequest {
    #[serde(rename = "spaceId")]
    space_id: String,
    #[serde(rename = "todoId")]
    todo_id: String,
    #[serde(rename = "isDone")]
    is_done: bool,
}

impl Backend {
    pub fn new(config: Config) -> Self {
        Self {
            config,
            pairing: None,
        }
    }

    pub fn run(mut self, mut socket: AppLoadSocket) -> Result<()> {
        loop {
            let Some(msg) = socket.recv()? else {
                break;
            };
            if msg.msg_type == MSG_SYSTEM_TERMINATE {
                break;
            }
            if msg.msg_type == MSG_SYSTEM_NEW_COORDINATOR {
                continue;
            }
            self.handle_message(&mut socket, msg)?;
        }
        Ok(())
    }

    fn handle_message(&mut self, socket: &mut AppLoadSocket, msg: Message) -> Result<()> {
        match msg.msg_type {
            MSG_GET_CONFIG => {
                let payload = ConfigPayload {
                    has_token: self.config.device_token.is_some(),
                    api_base_url: self.config.api_base_url().to_string(),
                    confirm_notebook_todos: self.config.confirm_notebook_todos(),
                    notebook_default_space_id: self.config.notebook_default_space_id.clone(),
                    notebook_default_space_name: self.config.notebook_default_space_name.clone(),
                    notebook_default_list_id: self.config.notebook_default_list_id.clone(),
                    notebook_default_list_name: self.config.notebook_default_list_name.clone(),
                    show_in_sidebar: self.config.show_in_sidebar(),
                };
                socket.send(MSG_GET_CONFIG_RESPONSE, &json!(payload).to_string())?;
            }
            MSG_SAVE_CONFIG => {
                let response = match serde_json::from_str::<SaveConfigRequest>(&msg.contents) {
                    Ok(req) => {
                        if let Some(token) = req.device_token {
                            self.config.device_token = Some(token);
                        }
                        if let Some(confirm) = req.confirm_notebook_todos {
                            self.config.confirm_notebook_todos = Some(confirm);
                        }
                        if req.clear_notebook_default_space {
                            self.config.notebook_default_space_id = None;
                            self.config.notebook_default_space_name = None;
                            self.config.notebook_default_list_id = None;
                            self.config.notebook_default_list_name = None;
                        } else if let Some(id) = req.notebook_default_space_id {
                            self.config
                                .set_notebook_default_space(id, req.notebook_default_space_name);
                        }
                        if req.clear_notebook_default_list {
                            self.config.notebook_default_list_id = None;
                            self.config.notebook_default_list_name = None;
                        } else if let Some(id) = req.notebook_default_list_id {
                            self.config.notebook_default_list_id = Some(id);
                            self.config.notebook_default_list_name = req.notebook_default_list_name;
                        }
                        if let Some(show) = req.show_in_sidebar {
                            self.config.show_in_sidebar = Some(show);
                        }
                        match self.config.save() {
                            Ok(()) => json!({
                                "ok": true,
                                "hasToken": self.config.device_token.is_some(),
                                "confirmNotebookTodos": self.config.confirm_notebook_todos(),
                                "notebookDefaultSpaceId": self.config.notebook_default_space_id,
                                "notebookDefaultSpaceName": self.config.notebook_default_space_name,
                                "notebookDefaultListId": self.config.notebook_default_list_id,
                                "notebookDefaultListName": self.config.notebook_default_list_name,
                                "showInSidebar": self.config.show_in_sidebar(),
                            }),
                            Err(err) => json!({ "ok": false, "error": err.to_string() }),
                        }
                    }
                    Err(err) => json!({ "ok": false, "error": err.to_string() }),
                };
                socket.send(MSG_SAVE_CONFIG_RESPONSE, &response.to_string())?;
            }
            MSG_LIST_TODOS => {
                let response = match self.client() {
                    Ok(client) => match client.list_items() {
                        Ok(listing) => json!({
                            "spaces": listing.spaces,
                            "activeSpaceId": listing.active_space_id,
                        }),
                        Err(err) => json!({ "error": err.to_string() }),
                    },
                    Err(err) => json!({ "error": err.to_string() }),
                };
                socket.send(MSG_LIST_TODOS_RESPONSE, &response.to_string())?;
            }
            MSG_SET_ACTIVE_SPACE => {
                let response = match serde_json::from_str::<SetActiveSpaceRequest>(&msg.contents) {
                    Ok(req) => match self.client() {
                        Ok(client) => match client.set_active_space(&req.space_id) {
                            Ok(()) => json!({ "ok": true }),
                            Err(err) => json!({ "error": err.to_string() }),
                        },
                        Err(err) => json!({ "error": err.to_string() }),
                    },
                    Err(err) => json!({ "error": err.to_string() }),
                };
                socket.send(MSG_SET_ACTIVE_SPACE_RESPONSE, &response.to_string())?;
            }
            MSG_CREATE_TODO => {
                let response = match serde_json::from_str::<CreateTodoRequest>(&msg.contents) {
                    Ok(req) => match self.client() {
                        Ok(client) => {
                            match client.create_todo(
                                &req.space_id,
                                &req.text,
                                req.parent_id.as_deref(),
                                req.is_list,
                            ) {
                                Ok(id) => json!({ "id": id }),
                                Err(err) => json!({ "error": err.to_string() }),
                            }
                        }
                        Err(err) => json!({ "error": err.to_string() }),
                    },
                    Err(err) => json!({ "error": err.to_string() }),
                };
                socket.send(MSG_CREATE_TODO_RESPONSE, &response.to_string())?;
            }
            MSG_CREATE_BOOKMARK => {
                let response = match serde_json::from_str::<CreateBookmarkRequest>(&msg.contents) {
                    Ok(req) => match self.client() {
                        Ok(client) => match client.create_bookmark(
                            &req.space_id,
                            &req.title,
                            &req.url,
                            req.is_list,
                            req.parent_id.as_deref(),
                        ) {
                            Ok(id) => json!({ "id": id }),
                            Err(err) => json!({ "error": err.to_string() }),
                        },
                        Err(err) => json!({ "error": err.to_string() }),
                    },
                    Err(err) => json!({ "error": err.to_string() }),
                };
                socket.send(MSG_CREATE_BOOKMARK_RESPONSE, &response.to_string())?;
            }
            MSG_CREATE_HABIT => {
                let response = match serde_json::from_str::<CreateHabitRequest>(&msg.contents) {
                    Ok(req) => match self.client() {
                        Ok(client) => {
                            match client.create_habit(&req.space_id, &req.name, &req.requirement) {
                                Ok(id) => json!({ "id": id }),
                                Err(err) => json!({ "error": err.to_string() }),
                            }
                        }
                        Err(err) => json!({ "error": err.to_string() }),
                    },
                    Err(err) => json!({ "error": err.to_string() }),
                };
                socket.send(MSG_CREATE_HABIT_RESPONSE, &response.to_string())?;
            }
            MSG_UPDATE_HABIT => {
                let response = match serde_json::from_str::<UpdateHabitRequest>(&msg.contents) {
                    Ok(req) => match self.client() {
                        Ok(client) => match client.update_habit(
                            &req.space_id,
                            &req.habit_id,
                            &req.name,
                            &req.requirement,
                        ) {
                            Ok(()) => json!({ "ok": true }),
                            Err(err) => json!({ "error": err.to_string() }),
                        },
                        Err(err) => json!({ "error": err.to_string() }),
                    },
                    Err(err) => json!({ "error": err.to_string() }),
                };
                socket.send(MSG_UPDATE_HABIT_RESPONSE, &response.to_string())?;
            }
            MSG_UPDATE_TODO => {
                let response = match serde_json::from_str::<UpdateTodoRequest>(&msg.contents) {
                    Ok(req) => match self.client() {
                        Ok(client) => {
                            match client.update_todo(&req.space_id, &req.todo_id, &req.text) {
                                Ok(()) => json!({ "ok": true }),
                                Err(err) => json!({ "error": err.to_string() }),
                            }
                        }
                        Err(err) => json!({ "error": err.to_string() }),
                    },
                    Err(err) => json!({ "error": err.to_string() }),
                };
                socket.send(MSG_UPDATE_TODO_RESPONSE, &response.to_string())?;
            }
            MSG_UPDATE_BOOKMARK => {
                let response = match serde_json::from_str::<UpdateBookmarkRequest>(&msg.contents) {
                    Ok(req) => match self.client() {
                        Ok(client) => match client.update_bookmark(
                            &req.space_id,
                            &req.bookmark_id,
                            &req.title,
                            &req.url,
                            req.is_list,
                        ) {
                            Ok(()) => json!({ "ok": true }),
                            Err(err) => json!({ "error": err.to_string() }),
                        },
                        Err(err) => json!({ "error": err.to_string() }),
                    },
                    Err(err) => json!({ "error": err.to_string() }),
                };
                socket.send(MSG_UPDATE_BOOKMARK_RESPONSE, &response.to_string())?;
            }
            MSG_SET_TODO_DONE => {
                let response = match serde_json::from_str::<SetTodoDoneRequest>(&msg.contents) {
                    Ok(req) => match self.client() {
                        Ok(client) => {
                            match client.set_todo_done(&req.space_id, &req.todo_id, req.is_done) {
                                Ok(()) => json!({ "ok": true }),
                                Err(err) => json!({ "error": err.to_string() }),
                            }
                        }
                        Err(err) => json!({ "error": err.to_string() }),
                    },
                    Err(err) => json!({ "error": err.to_string() }),
                };
                socket.send(MSG_SET_TODO_DONE_RESPONSE, &response.to_string())?;
            }
            MSG_SET_HABIT_COUNT => {
                let response = match serde_json::from_str::<SetHabitCountRequest>(&msg.contents) {
                    Ok(req) => match self.client() {
                        Ok(client) => {
                            match client.set_habit_count(&req.space_id, &req.habit_id, req.count) {
                                Ok(()) => json!({ "ok": true }),
                                Err(err) => json!({ "error": err.to_string() }),
                            }
                        }
                        Err(err) => json!({ "error": err.to_string() }),
                    },
                    Err(err) => json!({ "error": err.to_string() }),
                };
                socket.send(MSG_SET_HABIT_COUNT_RESPONSE, &response.to_string())?;
            }
            MSG_START_PAIRING => {
                let response = match self.start_pairing() {
                    Ok(value) => value,
                    Err(err) => json!({ "error": err.to_string() }),
                };
                socket.send(MSG_START_PAIRING_RESPONSE, &response.to_string())?;
            }
            MSG_POLL_PAIRING => {
                let response = match self.poll_pairing() {
                    Ok(value) => value,
                    Err(err) => json!({ "error": err.to_string() }),
                };
                socket.send(MSG_POLL_PAIRING_RESPONSE, &response.to_string())?;
            }
            MSG_UNLINK => {
                self.config.device_token = None;
                self.pairing = None;
                let response = match self.config.save() {
                    Ok(()) => json!({ "ok": true }),
                    Err(err) => json!({ "ok": false, "error": err.to_string() }),
                };
                socket.send(MSG_UNLINK_RESPONSE, &response.to_string())?;
            }
            other => {
                eprintln!("saver-remarkable: unhandled message type {other}");
            }
        }
        Ok(())
    }

    fn start_pairing(&mut self) -> Result<serde_json::Value> {
        let start = PairingClient::new(self.config.pairing_url()).start()?;
        let qr = qr_matrix(&start.verification_url_complete)?;

        let payload = json!({
            "userCode": start.user_code,
            "verificationUrl": start.verification_url,
            "expiresIn": start.expires_in,
            "interval": start.interval,
            "qr": qr,
        });
        self.pairing = Some(start);
        Ok(payload)
    }

    fn poll_pairing(&mut self) -> Result<serde_json::Value> {
        let Some(pairing) = self.pairing.as_ref() else {
            return Ok(json!({ "status": "expired" }));
        };

        let client = PairingClient::new(self.config.pairing_url());
        match client.poll(&pairing.user_code, &pairing.device_code)? {
            PairingStatus::Pending => Ok(json!({ "status": "pending" })),
            PairingStatus::Expired => {
                self.pairing = None;
                Ok(json!({ "status": "expired" }))
            }
            PairingStatus::Approved(token) => {
                self.pairing = None;
                self.config.device_token = Some(token);
                self.config.save()?;
                Ok(json!({ "status": "approved" }))
            }
        }
    }

    fn client(&self) -> Result<SaverClient> {
        let token = self.config.require_device_token()?;
        Ok(SaverClient::new(self.config.api_base_url(), token))
    }
}
