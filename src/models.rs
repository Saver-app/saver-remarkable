use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Todo {
    pub id: String,
    pub text: String,
    #[serde(rename = "isDone")]
    pub is_done: bool,
    #[serde(rename = "isList")]
    pub is_list: bool,
    #[serde(rename = "hasSubTodos")]
    pub has_sub_todos: bool,
    #[serde(rename = "parentId")]
    pub parent_id: Option<String>,
    #[serde(rename = "createdAt")]
    pub created_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Bookmark {
    pub id: String,
    pub title: String,
    pub url: Option<String>,
    #[serde(rename = "isList")]
    pub is_list: bool,
    #[serde(rename = "parentId")]
    pub parent_id: Option<String>,
    #[serde(rename = "createdAt")]
    pub created_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HabitRequirement {
    #[serde(rename = "requirementMode", default = "default_mode")]
    pub requirement_mode: String,
    #[serde(rename = "windowSizeDays", default = "default_week")]
    pub window_size_days: u32,
    #[serde(rename = "requiredDays", default = "default_week")]
    pub required_days: u32,
    #[serde(rename = "requiredCountPerDay", default = "default_one")]
    pub required_count_per_day: u32,
    #[serde(rename = "approvaleCount", default = "default_one")]
    pub approvale_count: u32,
    #[serde(rename = "anchorDate")]
    pub anchor_date: Option<String>,
}

fn default_mode() -> String {
    "everyday".to_string()
}
fn default_week() -> u32 {
    7
}
fn default_one() -> u32 {
    1
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Habit {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
    pub count: u32,
    #[serde(rename = "isDoneToday")]
    pub is_done_today: bool,
    pub streak: u32,
    #[serde(flatten)]
    pub requirement: HabitRequirement,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Space {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub todos: Vec<Todo>,
    #[serde(default)]
    pub bookmarks: Vec<Bookmark>,
    #[serde(default)]
    pub habits: Vec<Habit>,
}
