use std::collections::BTreeSet;
use std::fs::{self, File};
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

use anyhow::{anyhow, Context, Result};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

use crate::model::Recipe;
use crate::plan::Plan;

pub const STATUS_SCHEMA_VERSION: u32 = 1;
pub const LAST_APPLY_SCHEMA_VERSION: u32 = 1;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Status {
    #[serde(rename = "schemaVersion")]
    pub schema_version: u32,
    pub engine: EngineStatus,
    pub configured_recipe_count: Option<u64>,
    pub drift_count: Option<u64>,
    pub manual_residue_count: Option<u64>,
    pub last_apply: LastApply,
    pub verification: VerificationStatus,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EngineStatus {
    pub available: bool,
    pub version: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LastApply {
    pub status: Option<ApplyOutcome>,
    pub time: Option<String>,
    pub message: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ApplyOutcome {
    Succeeded,
    Partial,
    Declined,
    Failed,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct VerificationStatus {
    pub verified_recipe_count: Option<u64>,
    pub unverified_recipe_count: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LastApplyRecord {
    pub version: u32,
    pub status: ApplyOutcome,
    pub time: String,
    pub message: Option<String>,
}

impl Status {
    pub fn from_plan(
        recipes: &[Recipe],
        values: &Map<String, Value>,
        plan: &Plan,
        last_apply: LastApply,
        warnings: Vec<String>,
    ) -> Self {
        let configured = configured_recipes(recipes, values);
        let verified = configured
            .iter()
            .filter(|recipe| recipe.verified.is_some())
            .count() as u64;
        let configured_count = configured.len() as u64;

        Self {
            schema_version: STATUS_SCHEMA_VERSION,
            engine: EngineStatus {
                available: true,
                version: Some(env!("CARGO_PKG_VERSION").to_owned()),
            },
            configured_recipe_count: Some(configured_count),
            drift_count: Some(plan.summary.drift),
            manual_residue_count: Some(plan.summary.manual),
            last_apply,
            verification: VerificationStatus {
                verified_recipe_count: Some(verified),
                unverified_recipe_count: Some(configured_count - verified),
            },
            warnings: deduplicate(warnings),
        }
    }

    pub fn unavailable(warnings: Vec<String>) -> Self {
        Self {
            schema_version: STATUS_SCHEMA_VERSION,
            engine: EngineStatus {
                available: false,
                version: None,
            },
            configured_recipe_count: None,
            drift_count: None,
            manual_residue_count: None,
            last_apply: LastApply::default(),
            verification: VerificationStatus::default(),
            warnings: deduplicate(warnings),
        }
    }
}

pub fn configured_recipe_count(recipes: &[Recipe], values: &Map<String, Value>) -> usize {
    configured_recipes(recipes, values).len()
}

impl From<LastApplyRecord> for LastApply {
    fn from(record: LastApplyRecord) -> Self {
        Self {
            status: Some(record.status),
            time: Some(record.time),
            message: record.message,
        }
    }
}

pub fn last_apply_path(state_path: &Path) -> PathBuf {
    state_path.with_file_name("last-apply.json")
}

pub fn load_last_apply(path: &Path) -> (LastApply, Option<String>) {
    let text = match fs::read_to_string(path) {
        Ok(text) => text,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return (
                LastApply::default(),
                Some("The last app-state apply status is unavailable".to_owned()),
            );
        }
        Err(_) => {
            return (
                LastApply::default(),
                Some("The last app-state apply status is unavailable".to_owned()),
            );
        }
    };
    let record = match serde_json::from_str::<LastApplyRecord>(&text) {
        Ok(record) if record.version == LAST_APPLY_SCHEMA_VERSION && valid_time(&record.time) => {
            record
        }
        _ => {
            return (
                LastApply::default(),
                Some("The last app-state apply status is malformed".to_owned()),
            );
        }
    };
    (record.into(), None)
}

pub fn save_last_apply(state_path: &Path, record: &LastApplyRecord) -> Result<()> {
    if record.version != LAST_APPLY_SCHEMA_VERSION {
        return Err(anyhow!(
            "unsupported last-apply version {}; expected version {}",
            record.version,
            LAST_APPLY_SCHEMA_VERSION
        ));
    }
    if !valid_time(&record.time) {
        return Err(anyhow!("last-apply time is not RFC 3339: {}", record.time));
    }

    let path = last_apply_path(state_path);
    let parent = path
        .parent()
        .ok_or_else(|| anyhow!("last-apply path has no parent: {}", path.display()))?;
    fs::create_dir_all(parent)
        .with_context(|| format!("create last-apply directory {}", parent.display()))?;
    let mut temporary = tempfile::Builder::new()
        .prefix(".last-apply.")
        .tempfile_in(parent)
        .with_context(|| format!("create temporary last-apply file in {}", parent.display()))?;
    temporary
        .as_file()
        .set_permissions(fs::Permissions::from_mode(0o600))?;
    serde_json::to_writer_pretty(temporary.as_file_mut(), record)?;
    temporary.as_file_mut().write_all(b"\n")?;
    temporary.as_file_mut().sync_all()?;
    temporary
        .persist(&path)
        .map_err(|error| error.error)
        .with_context(|| format!("persist last-apply status to {}", path.display()))?;
    if let Err(error) = File::open(parent).and_then(|directory| directory.sync_all()) {
        if !matches!(
            error.kind(),
            std::io::ErrorKind::InvalidInput | std::io::ErrorKind::Unsupported
        ) {
            return Err(error).context("sync last-apply directory");
        }
    }
    Ok(())
}

pub fn record_last_apply(
    state_path: &Path,
    status: ApplyOutcome,
    time: String,
    message: Option<String>,
) -> Result<()> {
    save_last_apply(
        state_path,
        &LastApplyRecord {
            version: LAST_APPLY_SCHEMA_VERSION,
            status,
            time,
            message,
        },
    )
}

pub fn classify_apply(plan: &Plan) -> ApplyOutcome {
    let succeeded = plan
        .apps
        .iter()
        .flat_map(|app| &app.entries)
        .flat_map(|entry| &entry.actions)
        .filter(|action| action.result.as_deref() == Some("ok"))
        .count();
    if plan.exit_code == 0 {
        ApplyOutcome::Succeeded
    } else if plan.exit_code == 5 && succeeded == 0 {
        ApplyOutcome::Failed
    } else {
        ApplyOutcome::Partial
    }
}

pub fn apply_message(plan: &Plan, configured_recipe_count: usize) -> String {
    match classify_apply(plan) {
        ApplyOutcome::Succeeded => format!(
            "Applied {configured_recipe_count} configured recipe{}",
            if configured_recipe_count == 1 {
                ""
            } else {
                "s"
            }
        ),
        ApplyOutcome::Partial => {
            let (succeeded, failed, skipped) = action_results(plan);
            format!(
                "Apply completed partially: {succeeded} action(s) succeeded, {failed} failed, {skipped} skipped, {} drift, {} manual",
                plan.summary.drift, plan.summary.manual
            )
        }
        ApplyOutcome::Failed => {
            let (_, failed, skipped) = action_results(plan);
            format!("Apply failed: {failed} action(s) failed, {skipped} skipped")
        }
        ApplyOutcome::Declined => unreachable!("plans are never classified as declined"),
    }
}

fn action_results(plan: &Plan) -> (usize, usize, usize) {
    let mut succeeded = 0;
    let mut failed = 0;
    let mut skipped = 0;
    for result in plan
        .apps
        .iter()
        .flat_map(|app| &app.entries)
        .flat_map(|entry| &entry.actions)
        .filter_map(|action| action.result.as_deref())
    {
        match result {
            "ok" => succeeded += 1,
            "failed" => failed += 1,
            "skipped" => skipped += 1,
            _ => {}
        }
    }
    (succeeded, failed, skipped)
}

fn configured_recipes<'a>(recipes: &'a [Recipe], values: &Map<String, Value>) -> Vec<&'a Recipe> {
    recipes
        .iter()
        .filter(|recipe| values.contains_key(&recipe.id))
        .collect()
}

fn valid_time(value: &str) -> bool {
    plist::Date::from_xml_format(value).is_ok()
}

fn deduplicate(warnings: Vec<String>) -> Vec<String> {
    let mut seen = BTreeSet::new();
    warnings
        .into_iter()
        .filter(|warning| seen.insert(warning.clone()))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{ApplyPolicy, Verified};
    use crate::plan::Summary;
    use tempfile::TempDir;

    fn recipe(id: &str, verified: bool) -> Recipe {
        Recipe {
            schema_version: 1,
            id: id.to_owned(),
            name: id.to_owned(),
            bundle_id: format!("com.example.{id}"),
            install: None,
            detect: None,
            sandboxed: false,
            requires: vec![],
            config: vec![],
            apply: ApplyPolicy::default(),
            verified: verified.then(|| Verified {
                macos: "15.0".to_owned(),
                app: "1.0".to_owned(),
                date: "2026-10-05".to_owned(),
                harness: "0.1.0".to_owned(),
            }),
            maintainers: vec![],
            source_path: PathBuf::new(),
        }
    }

    fn plan(exit_code: i32) -> Plan {
        Plan {
            version: 1,
            generated_at: "2026-10-05T18:00:00Z".to_owned(),
            mode: "diff".to_owned(),
            apps: vec![],
            checklist: vec![],
            summary: Summary::default(),
            exit_code,
        }
    }

    #[test]
    fn configured_and_verified_counts_only_match_profile_recipe_ids() {
        let recipes = vec![recipe("configured", true), recipe("available", false)];
        let values = serde_json::json!({"configured": {}, "unknown": {}})
            .as_object()
            .unwrap()
            .clone();
        let status = Status::from_plan(&recipes, &values, &plan(0), LastApply::default(), vec![]);

        assert_eq!(status.configured_recipe_count, Some(1));
        assert_eq!(status.verification.verified_recipe_count, Some(1));
        assert_eq!(status.verification.unverified_recipe_count, Some(0));
    }

    #[test]
    fn zero_is_distinct_from_unknown() {
        let available = Status::from_plan(
            &[recipe("available", false)],
            &Map::new(),
            &plan(0),
            LastApply::default(),
            vec![],
        );
        let unavailable = Status::unavailable(vec![]);

        assert_eq!(available.configured_recipe_count, Some(0));
        assert_eq!(available.drift_count, Some(0));
        assert_eq!(unavailable.configured_recipe_count, None);
        assert_eq!(unavailable.drift_count, None);
    }

    #[test]
    fn last_apply_round_trips_all_outcomes() {
        let dir = TempDir::new().unwrap();
        let state_path = dir.path().join("apps.json");
        for outcome in [
            ApplyOutcome::Succeeded,
            ApplyOutcome::Partial,
            ApplyOutcome::Declined,
            ApplyOutcome::Failed,
        ] {
            record_last_apply(
                &state_path,
                outcome,
                "2026-10-05T18:00:00Z".to_owned(),
                Some("message".to_owned()),
            )
            .unwrap();
            let (last_apply, warning) = load_last_apply(&last_apply_path(&state_path));
            assert_eq!(warning, None);
            assert_eq!(last_apply.status, Some(outcome));
            assert_eq!(
                fs::metadata(last_apply_path(&state_path))
                    .unwrap()
                    .permissions()
                    .mode()
                    & 0o777,
                0o600
            );
        }
    }

    #[test]
    fn malformed_last_apply_is_not_mutated() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("last-apply.json");
        fs::write(&path, "{broken").unwrap();

        let (last_apply, warning) = load_last_apply(&path);

        assert_eq!(last_apply, LastApply::default());
        assert_eq!(
            warning.as_deref(),
            Some("The last app-state apply status is malformed")
        );
        assert_eq!(fs::read_to_string(path).unwrap(), "{broken");
    }
}
