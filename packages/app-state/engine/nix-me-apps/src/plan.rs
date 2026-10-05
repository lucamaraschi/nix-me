use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Plan {
    pub version: u32,
    pub generated_at: String,
    pub mode: String,
    pub apps: Vec<AppPlan>,
    pub checklist: Vec<ChecklistItem>,
    pub summary: Summary,
    pub exit_code: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppPlan {
    pub id: String,
    pub verified: Option<VerifiedPlan>,
    pub entries: Vec<EntryPlan>,
    pub pokes: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VerifiedPlan {
    pub macos: String,
    pub app: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EntryPlan {
    pub bind: String,
    pub kind: String,
    pub confirm: String,
    pub actions: Vec<Action>,
    pub drift: Vec<Drift>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Action {
    pub op: String,
    pub target: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub current: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub desired: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub value_type: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Drift {
    pub target: String,
    pub reason: String,
    pub detail: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChecklistItem {
    pub app: String,
    pub step: String,
    pub confirm: String,
    pub satisfied: bool,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Summary {
    pub writes: u64,
    pub adds: u64,
    pub dels: u64,
    pub files: u64,
    pub materialize: u64,
    pub drift: u64,
    pub manual: u64,
}

impl Plan {
    pub fn recompute_summary_and_exit(&mut self, apply: bool, failed: bool) {
        let mut summary = Summary::default();
        for app in &self.apps {
            for entry in &app.entries {
                summary.drift += entry.drift.len() as u64;
                for action in &entry.actions {
                    match action.op.as_str() {
                        "write" => summary.writes += 1,
                        "add" => summary.adds += 1,
                        "del" => summary.dels += 1,
                        "replace_file" | "merge_file" => summary.files += 1,
                        "materialize" => summary.materialize += 1,
                        _ => {}
                    }
                }
            }
        }
        summary.manual = self.checklist.iter().filter(|c| !c.satisfied).count() as u64;
        self.summary = summary;
        self.exit_code = if failed {
            5
        } else if self.summary.drift > 0 {
            2
        } else if !apply
            && (self.summary.writes
                + self.summary.adds
                + self.summary.dels
                + self.summary.files
                + self.summary.materialize)
                > 0
        {
            2
        } else if self.summary.manual > 0 {
            3
        } else {
            0
        };
    }

    pub fn has_actions(&self) -> bool {
        self.apps
            .iter()
            .any(|a| a.entries.iter().any(|e| !e.actions.is_empty()))
    }
}

pub fn confirm_name(value: crate::model::Confirm) -> String {
    match value {
        crate::model::Confirm::None => "none",
        crate::model::Confirm::OneClick => "one_click",
        crate::model::Confirm::FullManual => "full_manual",
    }
    .into()
}
