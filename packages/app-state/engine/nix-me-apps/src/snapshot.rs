use std::collections::BTreeSet;

use serde_json::{Map, Value};

use crate::capture::redact_secrets;
use crate::engine::{read_file_owned, resolve_file_path};
use crate::model::{ConfigEntry, FileExport, FileFormat, Recipe};
use crate::prefs::PrefStore;
use crate::runner::CommandRunner;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct SnapshotOptions {
    pub confirm_reviewed_text: bool,
}

/// Read the current values owned by recipes without mutating application state.
pub fn current_values<P: PrefStore, R: CommandRunner>(
    recipes: &[Recipe],
    only: &BTreeSet<String>,
    prefs: &P,
    runner: &mut R,
) -> Value {
    current_values_with_options(recipes, only, prefs, runner, SnapshotOptions::default())
}

/// Read current values, including recipe-reviewed text only when separately confirmed.
pub fn current_values_with_options<P: PrefStore, R: CommandRunner>(
    recipes: &[Recipe],
    only: &BTreeSet<String>,
    prefs: &P,
    runner: &mut R,
    options: SnapshotOptions,
) -> Value {
    let mut values = Map::new();
    let mut applications = Vec::new();
    let mut all_redactions = Vec::new();

    for recipe in recipes {
        if !only.is_empty() && !only.contains(&recipe.id) {
            continue;
        }

        let gate = if crate::engine::recipe_is_installed(recipe, runner) {
            crate::engine::verify_recipe_version(recipe, runner, false)
        } else {
            Err(anyhow::anyhow!("application is not installed"))
        };
        if let Err(error) = gate {
            values.insert(recipe.id.clone(), Value::Object(Map::new()));
            applications.push(serde_json::json!({
                "id":recipe.id,
                "name":recipe.name,
                "bundleId":recipe.bundle_id,
                "captured":[],
                "skipped":[{
                    "kind":"application",
                    "bind":Value::Null,
                    "reason":format!("capture gate refused access: {error:#}")
                }]
            }));
            continue;
        }

        let defaults_count = recipe
            .config
            .iter()
            .filter(|entry| matches!(entry, ConfigEntry::Defaults(_)))
            .count();
        let mut app_values = Map::new();
        let mut captured = Vec::new();
        let mut skipped = Vec::new();

        for entry in &recipe.config {
            match entry {
                ConfigEntry::Defaults(defaults) => {
                    let mut current = Map::new();
                    for (key, schema) in &defaults.keys {
                        match prefs.read(&defaults.domain, key, schema.host) {
                            Ok(Some(value)) => {
                                current.insert(key.clone(), value);
                            }
                            Ok(None) => {}
                            Err(error) => skipped.push(serde_json::json!({
                                "kind":"defaults",
                                "bind":defaults.binds.as_deref().unwrap_or("defaults"),
                                "reason":format!("could not read {}/{}: {error}", defaults.domain, key)
                            })),
                        }
                    }
                    if current.is_empty() {
                        skipped.push(serde_json::json!({
                            "kind":"defaults",
                            "bind":defaults.binds.as_deref().unwrap_or("defaults"),
                            "reason":"no declared values were present"
                        }));
                    } else {
                        let count = current.len();
                        if defaults.binds.is_none() && defaults_count == 1 {
                            app_values.extend(current);
                        } else {
                            app_values.insert(
                                defaults.binds.clone().unwrap_or_else(|| "defaults".into()),
                                Value::Object(current),
                            );
                        }
                        captured.push(serde_json::json!({
                            "kind":"defaults",
                            "bind":defaults.binds.as_deref().unwrap_or("defaults"),
                            "valueCount":count
                        }));
                    }
                }
                ConfigEntry::File(file)
                    if file.paths.is_some()
                        || (file.export == FileExport::ReviewedText
                            && options.confirm_reviewed_text) =>
                {
                    let bind = file.binds.as_deref().unwrap_or("file");
                    match resolve_file_path(recipe, &file.path) {
                        Ok(path) if path.exists() => match read_file_owned(&path, file) {
                            Ok(value) => {
                                app_values.insert(bind.into(), value);
                                captured.push(serde_json::json!({
                                    "kind":"file",
                                    "bind":bind,
                                    "valueCount":1
                                }));
                            }
                            Err(error) => skipped.push(serde_json::json!({
                                "kind":"file",
                                "bind":bind,
                                "reason":format!("could not read {}: {error}", path.display())
                            })),
                        },
                        Ok(path) => skipped.push(serde_json::json!({
                            "kind":"file",
                            "bind":bind,
                            "reason":format!("{} does not exist", path.display())
                        })),
                        Err(error) => skipped.push(serde_json::json!({
                            "kind":"file",
                            "bind":bind,
                            "reason":error.to_string()
                        })),
                    }
                }
                ConfigEntry::File(file) => {
                    let reason = if file.format != FileFormat::Text && file.paths.is_none() {
                        "structured file export requires an explicit path allowlist"
                    } else if file.export == FileExport::ReviewedText {
                        "reviewed text export requires explicit caller confirmation"
                    } else {
                        "text file is not opted into reviewed export"
                    };
                    skipped.push(serde_json::json!({
                        "kind":"file",
                        "bind":file.binds.as_deref().unwrap_or("file"),
                        "reason":reason
                    }));
                }
                ConfigEntry::Command(command) => match runner.run(&command.list.get) {
                    Ok(output) => {
                        let items = output
                            .lines()
                            .map(str::trim)
                            .filter(|item| !item.is_empty())
                            .map(|item| Value::String(item.to_owned()))
                            .collect::<Vec<_>>();
                        let count = items.len();
                        app_values.insert(command.name.clone(), Value::Array(items));
                        captured.push(serde_json::json!({
                            "kind":"command",
                            "bind":command.name,
                            "valueCount":count
                        }));
                    }
                    Err(error) => skipped.push(serde_json::json!({
                        "kind":"command",
                        "bind":command.name,
                        "reason":error.to_string()
                    })),
                },
                ConfigEntry::CommandValue(command) => {
                    match runner.run_owned(&command.get.executable, &command.get.arguments) {
                        Ok(output) => {
                            match crate::engine::parse_command_value(&output, command.value_type) {
                                Ok(value) => {
                                    app_values.insert(command.name.clone(), value);
                                    captured.push(serde_json::json!({
                                        "kind":"command_value",
                                        "bind":command.name,
                                        "valueCount":1
                                    }));
                                }
                                Err(error) => skipped.push(serde_json::json!({
                                    "kind":"command_value",
                                    "bind":command.name,
                                    "reason":error.to_string()
                                })),
                            }
                        }
                        Err(error) => skipped.push(serde_json::json!({
                            "kind":"command_value",
                            "bind":command.name,
                            "reason":error.to_string()
                        })),
                    }
                }
                ConfigEntry::Accessibility(accessibility) => {
                    let result =
                        crate::engine::verify_accessibility_permission(recipe).and_then(|_| {
                            crate::accessibility::inspect(runner, &recipe.bundle_id, accessibility)
                        });
                    match result {
                        Ok(value) => {
                            app_values.insert(
                                accessibility.name.clone(),
                                serde_json::json!({
                                    "expected":value.clone(),
                                    "desired":value
                                }),
                            );
                            captured.push(serde_json::json!({
                                "kind":"accessibility",
                                "bind":accessibility.name,
                                "valueCount":1
                            }));
                        }
                        Err(error) => skipped.push(serde_json::json!({
                            "kind":"accessibility",
                            "bind":accessibility.name,
                            "reason":error.to_string()
                        })),
                    }
                }
                ConfigEntry::GeneratedImport(import) => skipped.push(serde_json::json!({
                    "kind":"generated_import",
                    "bind":import.source,
                    "reason":"generated imports cannot be reconstructed from installed state"
                })),
                ConfigEntry::Manual(_) => skipped.push(serde_json::json!({
                    "kind":"manual",
                    "bind":Value::Null,
                    "reason":"manual steps do not expose machine-readable state"
                })),
            }
        }

        let mut app_value = Value::Object(app_values);
        let redactions = redact_secrets(&mut app_value, &BTreeSet::new());
        remove_null_array_items(&mut app_value);
        all_redactions.extend(redactions.into_iter().map(|redaction| {
            serde_json::json!({
                "path":format!("{}.{}", recipe.id, redaction.path),
                "reason":redaction.reason,
                "action":redaction.action
            })
        }));
        values.insert(recipe.id.clone(), app_value);
        applications.push(serde_json::json!({
            "id":recipe.id,
            "name":recipe.name,
            "bundleId":recipe.bundle_id,
            "captured":captured,
            "skipped":skipped
        }));
    }

    serde_json::json!({
        "version":1,
        "values":values,
        "applications":applications,
        "redaction":{
            "policy":"default_closed",
            "count":all_redactions.len(),
            "items":all_redactions
        }
    })
}

fn remove_null_array_items(value: &mut Value) {
    match value {
        Value::Array(items) => {
            items.retain(|item| !item.is_null());
            for item in items {
                remove_null_array_items(item);
            }
        }
        Value::Object(map) => {
            for item in map.values_mut() {
                remove_null_array_items(item);
            }
        }
        _ => {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::load_recipe;
    use crate::prefs::FakePrefStore;
    use crate::runner::ReplayCommandRunner;
    use tempfile::TempDir;

    #[test]
    fn captures_declared_defaults_and_redacts_secrets() {
        let directory = TempDir::new().unwrap();
        let recipe_path = directory.path().join("fixture.yaml");
        std::fs::write(
            &recipe_path,
            "schema_version: 1\nid: fixture\nname: Fixture\nbundle_id: com.example.fixture\nconfig:\n  - kind: defaults\n    domain: com.example.fixture\n    keys:\n      enabled: {type: bool}\n      apiToken: {type: string}\n",
        )
        .unwrap();
        let recipe = load_recipe(&recipe_path).unwrap();
        let mut prefs = FakePrefStore::default();
        prefs.set(
            "com.example.fixture",
            "enabled",
            crate::model::Host::Any,
            Value::Bool(true),
        );
        prefs.set(
            "com.example.fixture",
            "apiToken",
            crate::model::Host::Any,
            Value::String("not-for-the-repository".into()),
        );
        let mut runner = ReplayCommandRunner::default();

        let report = current_values(&[recipe], &BTreeSet::new(), &prefs, &mut runner);

        assert_eq!(report["values"]["fixture"]["enabled"], true);
        assert!(report["values"]["fixture"].get("apiToken").is_none());
        assert_eq!(report["redaction"]["count"], 1);
    }

    #[test]
    fn reviewed_text_requires_recipe_opt_in_and_caller_confirmation() {
        let directory = TempDir::new().unwrap();
        let config_path = directory.path().join("settings.conf");
        let exact = "theme = dark\n\n# keep this final newline\n";
        std::fs::write(&config_path, exact).unwrap();
        let recipe_path = directory.path().join("fixture.yaml");
        std::fs::write(
            &recipe_path,
            format!(
                "schema_version: 1\nid: fixture\nname: Fixture\nbundle_id: com.example.fixture\nconfig:\n  - kind: file\n    path: {:?}\n    format: text\n    export: reviewed_text\n",
                config_path.display().to_string()
            ),
        )
        .unwrap();
        let recipe = load_recipe(&recipe_path).unwrap();
        let prefs = FakePrefStore::default();
        let mut runner = ReplayCommandRunner::default();

        let closed = current_values(
            std::slice::from_ref(&recipe),
            &BTreeSet::new(),
            &prefs,
            &mut runner,
        );
        assert_eq!(closed["values"]["fixture"], serde_json::json!({}));
        assert_eq!(
            closed["applications"][0]["skipped"][0]["reason"],
            "reviewed text export requires explicit caller confirmation"
        );

        let confirmed = current_values_with_options(
            &[recipe],
            &BTreeSet::new(),
            &prefs,
            &mut runner,
            SnapshotOptions {
                confirm_reviewed_text: true,
            },
        );
        assert_eq!(confirmed["values"]["fixture"]["file"], exact);
        assert_eq!(confirmed["applications"][0]["captured"][0]["kind"], "file");
        assert_eq!(confirmed["applications"][0]["captured"][0]["valueCount"], 1);
    }

    #[test]
    fn unreviewed_text_stays_closed_even_when_caller_confirms() {
        let directory = TempDir::new().unwrap();
        let config_path = directory.path().join("settings.conf");
        std::fs::write(&config_path, "private = value\n").unwrap();
        let recipe_path = directory.path().join("fixture.yaml");
        std::fs::write(
            &recipe_path,
            format!(
                "schema_version: 1\nid: fixture\nname: Fixture\nbundle_id: com.example.fixture\nconfig:\n  - kind: file\n    path: {:?}\n    format: text\n",
                config_path.display().to_string()
            ),
        )
        .unwrap();
        let recipe = load_recipe(&recipe_path).unwrap();
        let prefs = FakePrefStore::default();
        let mut runner = ReplayCommandRunner::default();

        let report = current_values_with_options(
            &[recipe],
            &BTreeSet::new(),
            &prefs,
            &mut runner,
            SnapshotOptions {
                confirm_reviewed_text: true,
            },
        );

        assert_eq!(report["values"]["fixture"], serde_json::json!({}));
        assert_eq!(
            report["applications"][0]["skipped"][0]["reason"],
            "text file is not opted into reviewed export"
        );
    }

    #[test]
    fn capture_gates_missing_and_unsupported_apps_before_any_entry_read() {
        let directory = TempDir::new().unwrap();
        let missing_recipe_path = directory.path().join("missing.yaml");
        std::fs::write(
            &missing_recipe_path,
            "schema_version: 1\nid: missing\nname: Missing\nbundle_id: com.example.missing\ndetect: {app_path: /definitely/not/installed.app}\nconfig:\n  - kind: defaults\n    domain: com.example.missing\n    keys: {enabled: {type: bool}}\n",
        )
        .unwrap();
        let unsupported_recipe_path = directory.path().join("unsupported.yaml");
        std::fs::write(
            &unsupported_recipe_path,
            "schema_version: 1\nid: unsupported\nname: Unsupported\nbundle_id: com.example.unsupported\napp_version:\n  command: app --version\n  supported_majors: [4]\nconfig:\n  - kind: command_value\n    name: enabled\n    type: bool\n    get: {executable: /usr/bin/tool, arguments: [get]}\n    set: {executable: /usr/bin/tool, arguments: [set, '{value}']}\n",
        )
        .unwrap();
        let missing = load_recipe(&missing_recipe_path).unwrap();
        let unsupported = load_recipe(&unsupported_recipe_path).unwrap();
        let mut prefs = FakePrefStore::default();
        prefs.set(
            "com.example.missing",
            "enabled",
            crate::model::Host::Any,
            Value::Bool(true),
        );
        let mut runner = ReplayCommandRunner::default();
        runner
            .outputs
            .insert("app --version".into(), Ok("App 5.0.0".into()));

        let report = current_values(
            &[missing, unsupported],
            &BTreeSet::new(),
            &prefs,
            &mut runner,
        );

        assert_eq!(report["values"]["missing"], serde_json::json!({}));
        assert_eq!(report["values"]["unsupported"], serde_json::json!({}));
        assert_eq!(runner.recorded, ["app --version"]);
        assert!(report["applications"][0]["skipped"][0]["reason"]
            .as_str()
            .unwrap()
            .contains("capture gate refused access"));
        assert!(report["applications"][1]["skipped"][0]["reason"]
            .as_str()
            .unwrap()
            .contains("unsupported application major version 5"));
    }
}
