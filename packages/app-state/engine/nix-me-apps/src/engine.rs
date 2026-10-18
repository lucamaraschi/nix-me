use std::collections::BTreeSet;
use std::fs;
use std::io::Write;
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::path::{Path, PathBuf};

use anyhow::{anyhow, bail, Context, Result};
use base64::Engine as _;
use serde_json::{Map, Value};
use sha2::{Digest, Sha256};

use crate::model::*;
use crate::plan::*;
use crate::prefs::PrefStore;
use crate::runner::{render_owned_command, Clock, CommandRunner};
use crate::state::{ArtifactState, State};

#[derive(Debug, Clone, Default)]
pub struct Options {
    pub force: bool,
    pub skip_manual: bool,
    pub skip_missing: bool,
    pub require_verified: bool,
    pub no_exec: bool,
}

pub struct Engine<'a, P: PrefStore, R: CommandRunner, C: Clock> {
    pub prefs: &'a mut P,
    pub runner: &'a mut R,
    pub clock: &'a C,
    pub state: &'a mut State,
    pub state_dir: PathBuf,
    pub options: Options,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone)]
enum UndoAction {
    Defaults {
        domain: String,
        key: String,
        host: Host,
        value_type: ValueType,
        previous: Option<Value>,
    },
    File {
        path: PathBuf,
        previous: Option<Vec<u8>>,
        mode: Option<u32>,
    },
    CommandSet {
        entry: CommandEntry,
        previous: BTreeSet<String>,
    },
    CommandValue {
        entry: CommandValueEntry,
        previous: Value,
    },
    Accessibility {
        bundle_id: String,
        entry: AccessibilityEntry,
        previous: Value,
        applied: Value,
    },
    None,
}

impl<'a, P: PrefStore, R: CommandRunner, C: Clock> Engine<'a, P, R, C> {
    pub fn plan(
        &mut self,
        recipes: &[Recipe],
        values: &Map<String, Value>,
        mode: &str,
    ) -> Result<Plan> {
        let mut plan = Plan {
            version: 1,
            generated_at: self.clock.now(),
            mode: mode.into(),
            apps: vec![],
            checklist: vec![],
            summary: Summary::default(),
            exit_code: 0,
        };
        let mut active = BTreeSet::new();
        let mut preflight_errors = Vec::new();
        for recipe in recipes {
            if !values.contains_key(&recipe.id) {
                continue;
            }
            if self.options.require_verified && recipe.verified.is_none() {
                preflight_errors.push(format!(
                    "recipe {} is unverified (--require-verified)",
                    recipe.id
                ));
                continue;
            }
            if recipe.verified.is_none() {
                self.warnings
                    .push(format!("recipe {} is unverified", recipe.id));
            }
            if !recipe_is_installed(recipe, self.runner) {
                if self.options.skip_missing {
                    self.warnings
                        .push(format!("{} is not installed; skipped", recipe.name));
                } else {
                    preflight_errors.push(format!(
                        "{} is not installed (use --skip-missing to warn and skip)",
                        recipe.name
                    ));
                }
                continue;
            }
            if let Err(error) = self.preflight(recipe) {
                preflight_errors.push(format!("{error:#}"));
                continue;
            }
            active.insert(recipe.id.clone());
        }
        if !preflight_errors.is_empty() {
            bail!("preflight failed:\n  - {}", preflight_errors.join("\n  - "));
        }
        for recipe in recipes {
            if !active.contains(&recipe.id) {
                continue;
            }
            let Some(app_values) = values.get(&recipe.id) else {
                continue;
            };
            let models = self.bind_models(recipe, app_values, values)?;
            let mut app_plan = AppPlan {
                id: recipe.id.clone(),
                verified: recipe.verified.as_ref().map(|v| VerifiedPlan {
                    macos: v.macos.clone(),
                    app: v.app.clone(),
                }),
                entries: vec![],
                pokes: vec![],
            };
            for (index, entry) in recipe.config.iter().enumerate() {
                let bind = entry.bind().unwrap_or_else(|| format!("manual-{index}"));
                let mut ep = EntryPlan {
                    bind: bind.clone(),
                    kind: entry.kind().into(),
                    confirm: confirm_name(entry.confirm()),
                    actions: vec![],
                    drift: vec![],
                };
                match entry {
                    ConfigEntry::Defaults(e) => {
                        self.plan_defaults(recipe, e, models[index].as_ref().unwrap(), &mut ep)?
                    }
                    ConfigEntry::File(e) => {
                        self.plan_file(recipe, e, models[index].as_ref().unwrap(), &mut ep)?
                    }
                    ConfigEntry::Command(e) => {
                        self.plan_command(e, models[index].as_ref().unwrap(), &mut ep)?
                    }
                    ConfigEntry::CommandValue(e) => {
                        self.plan_command_value(e, models[index].as_ref().unwrap(), &mut ep)?
                    }
                    ConfigEntry::Accessibility(e) => self.plan_accessibility(
                        recipe,
                        e,
                        models[index].as_ref().unwrap(),
                        &mut ep,
                    )?,
                    ConfigEntry::GeneratedImport(e) => self.plan_import(
                        recipe,
                        e,
                        models[index].as_ref().unwrap(),
                        &mut ep,
                        &mut plan.checklist,
                    )?,
                    ConfigEntry::Manual(e) => self.plan_manual(recipe, e, &mut plan.checklist)?,
                }
                app_plan.entries.push(ep);
            }
            if app_plan.entries.iter().any(|e| !e.actions.is_empty()) {
                match recipe.apply.poke {
                    Poke::None => {}
                    Poke::Cfprefsd => app_plan.pokes.push("cfprefsd".into()),
                    Poke::RestartApp => app_plan.pokes.push("restart_app".into()),
                    Poke::Script => app_plan.pokes.push("script".into()),
                }
            }
            plan.apps.push(app_plan);
        }
        if self.options.skip_manual {
            plan.checklist.clear();
        }
        plan.recompute_summary_and_exit(false, false);
        Ok(plan)
    }

    fn preflight(&mut self, recipe: &Recipe) -> Result<()> {
        verify_recipe_version(recipe, self.runner, self.options.no_exec)?;
        if recipe.sandboxed {
            let root = home_dir()?
                .join("Library/Containers")
                .join(&recipe.bundle_id)
                .join("Data");
            if root.exists() && !root.read_dir().is_ok() {
                bail!("{} needs Full Disk Access: System Settings > Privacy & Security > Full Disk Access",recipe.name);
            }
        }
        #[cfg(not(target_os = "macos"))]
        if recipe
            .config
            .iter()
            .any(|entry| matches!(entry, ConfigEntry::Accessibility(_)))
            && !self.options.no_exec
        {
            bail!("{} Accessibility actions require macOS", recipe.name);
        }
        #[cfg(target_os = "macos")]
        for requirement in &recipe.requires {
            if requirement == "full_disk_access" {
                let root = home_dir()?
                    .join("Library/Containers")
                    .join(&recipe.bundle_id)
                    .join("Data");
                if root.exists() && !root.read_dir().is_ok() {
                    bail!("{} requires Full Disk Access: System Settings > Privacy & Security > Full Disk Access",recipe.name);
                }
            } else if requirement == "accessibility"
                && !self.options.no_exec
                && !mac_permissions::accessibility_granted()
            {
                bail!("{} requires Accessibility: System Settings > Privacy & Security > Accessibility",recipe.name);
            } else if requirement == "input_monitoring"
                && !mac_permissions::input_monitoring_granted()
            {
                bail!("{} requires Input Monitoring: System Settings > Privacy & Security > Input Monitoring",recipe.name);
            } else if requirement == "screen_recording"
                && !mac_permissions::screen_recording_granted()
            {
                bail!("{} requires Screen Recording: System Settings > Privacy & Security > Screen & System Audio Recording",recipe.name);
            }
        }
        Ok(())
    }

    fn bind_models(
        &mut self,
        recipe: &Recipe,
        app_values: &Value,
        all_values: &Map<String, Value>,
    ) -> Result<Vec<Option<Value>>> {
        let map = app_values.as_object().ok_or_else(|| {
            anyhow!(
                "{}: profile.{} must be a map",
                recipe.source_path.display(),
                recipe.id
            )
        })?;
        let default_indices = recipe
            .config
            .iter()
            .enumerate()
            .filter_map(|(i, e)| matches!(e, ConfigEntry::Defaults(_)).then_some(i))
            .collect::<Vec<_>>();
        let named = recipe
            .config
            .iter()
            .filter_map(ConfigEntry::bind)
            .filter(|b| !b.starts_with("profile."))
            .collect::<BTreeSet<_>>();
        let source_roots = recipe
            .config
            .iter()
            .filter_map(|e| {
                if let ConfigEntry::GeneratedImport(g) = e {
                    g.source
                        .strip_prefix(&format!("profile.{}.", recipe.id))
                        .and_then(|p| p.split('.').next())
                        .map(str::to_owned)
                } else {
                    None
                }
            })
            .collect::<BTreeSet<_>>();
        let loose = map
            .keys()
            .filter(|k| !named.contains(*k) && !source_roots.contains(*k))
            .cloned()
            .collect::<Vec<_>>();
        if !loose.is_empty() && default_indices.len() != 1 {
            bail!("{}: profile.{} keys [{}] do not match valid bind names [{}]; root-bind sugar requires exactly one defaults entry",recipe.source_path.display(),recipe.id,loose.join(", "),named.into_iter().collect::<Vec<_>>().join(", "));
        }
        let mut result = vec![None; recipe.config.len()];
        for (index, entry) in recipe.config.iter().enumerate() {
            match entry {
                ConfigEntry::Defaults(e) => {
                    let bind = e.binds.as_deref().unwrap_or("defaults");
                    let mut model = Map::new();
                    if default_indices.len() == 1 && default_indices[0] == index {
                        for key in &loose {
                            model.insert(key.clone(), map[key].clone());
                        }
                    }
                    if let Some(explicit) = map.get(bind) {
                        let explicit = explicit.as_object().ok_or_else(|| {
                            anyhow!(
                                "{}: profile.{}.{} must be a map",
                                recipe.source_path.display(),
                                recipe.id,
                                bind
                            )
                        })?;
                        for (k, v) in explicit {
                            if model.insert(k.clone(), v.clone()).is_some() {
                                self.warnings.push(format!(
                                    "profile.{}.{} overrides root-bound key {}",
                                    recipe.id, bind, k
                                ));
                            }
                        }
                    }
                    result[index] = Some(Value::Object(model));
                }
                ConfigEntry::File(e) => {
                    let bind = e.binds.as_deref().unwrap_or("file");
                    result[index] = Some(map.get(bind).cloned().ok_or_else(|| {
                        anyhow!(
                            "{}: missing profile.{}.{}",
                            recipe.source_path.display(),
                            recipe.id,
                            bind
                        )
                    })?);
                }
                ConfigEntry::Command(e) => {
                    result[index] = Some(
                        map.get(&e.name)
                            .cloned()
                            .unwrap_or_else(|| Value::Array(vec![])),
                    );
                }
                ConfigEntry::CommandValue(e) => {
                    result[index] = Some(map.get(&e.name).cloned().ok_or_else(|| {
                        anyhow!(
                            "{}: missing profile.{}.{}",
                            recipe.source_path.display(),
                            recipe.id,
                            e.name
                        )
                    })?);
                }
                ConfigEntry::Accessibility(e) => {
                    result[index] = Some(map.get(&e.name).cloned().ok_or_else(|| {
                        anyhow!(
                            "{}: missing profile.{}.{}",
                            recipe.source_path.display(),
                            recipe.id,
                            e.name
                        )
                    })?);
                }
                ConfigEntry::GeneratedImport(e) => {
                    result[index] = Some(
                        lookup_source(all_values, &e.source)
                            .cloned()
                            .ok_or_else(|| {
                                anyhow!(
                                    "{}: generated_import source {} does not exist",
                                    recipe.source_path.display(),
                                    e.source
                                )
                            })?,
                    );
                }
                ConfigEntry::Manual(_) => {}
            }
        }
        Ok(result)
    }

    fn plan_defaults(
        &mut self,
        recipe: &Recipe,
        e: &DefaultsEntry,
        model: &Value,
        plan: &mut EntryPlan,
    ) -> Result<()> {
        if e.domain == "NSGlobalDomain" {
            self.warnings.push(format!(
                "{} writes NSGlobalDomain; changes may require app relaunch or re-login",
                recipe.id
            ));
        }
        let map = model
            .as_object()
            .ok_or_else(|| anyhow!("profile.{}.{} must be a map", recipe.id, plan.bind))?;
        for (key, value) in map {
            let (schema, ty) = if let Some(schema) = e.keys.get(key) {
                if !validate_value_type(value, schema.value_type) {
                    bail!(
                        "{}: profile.{}.{}.{} has wrong type; expected {}",
                        recipe.source_path.display(),
                        recipe.id,
                        plan.bind,
                        key,
                        schema.value_type.as_str()
                    );
                }
                (Some(schema), schema.value_type)
            } else {
                if e.unknown_keys == UnknownKeys::Reject {
                    bail!(
                        "{}: unknown defaults key profile.{}.{}.{}",
                        recipe.source_path.display(),
                        recipe.id,
                        plan.bind,
                        key
                    );
                }
                self.warnings.push(format!(
                    "{}: passing through unknown key {}",
                    recipe.id, key
                ));
                (None, infer_type(value)?)
            };
            if ty == ValueType::Data {
                base64::engine::general_purpose::STANDARD
                    .decode(value.as_str().unwrap())
                    .with_context(|| {
                        format!("profile.{}.{}.{} must be base64", recipe.id, plan.bind, key)
                    })?;
            }
            if ty == ValueType::Date && !is_rfc3339(value.as_str().unwrap()) {
                bail!(
                    "profile.{}.{}.{} must be RFC 3339",
                    recipe.id,
                    plan.bind,
                    key
                );
            }
            let host = schema.map(|s| s.host).unwrap_or_default();
            let desired = coerce(value, ty)?;
            let current = self.prefs.read(&e.domain, key, host)?;
            if self.prefs.is_forced(&e.domain, key)? {
                if current.as_ref() != Some(&desired) {
                    plan.drift.push(Drift {
                        target: format!("{}/{}", e.domain, key),
                        reason: "managed".into(),
                        detail: "key is MDM-forced".into(),
                    });
                }
                continue;
            }
            if !equal_typed(current.as_ref(), &desired, ty) {
                plan.actions.push(Action {
                    op: "write".into(),
                    target: format!("{}/{}", e.domain, key),
                    current,
                    desired: Some(desired),
                    value_type: Some(ty.as_str().into()),
                    result: None,
                    error: None,
                });
            }
        }
        Ok(())
    }

    fn plan_file(
        &mut self,
        recipe: &Recipe,
        e: &FileEntry,
        model: &Value,
        plan: &mut EntryPlan,
    ) -> Result<()> {
        validate_file_model(recipe, e, model, &plan.bind)?;
        let path = resolve_file_path(recipe, &e.path)?;
        let current_full = if path.exists() {
            Some(read_structured(&path, e.format)?)
        } else {
            None
        };
        let current = current_full
            .as_ref()
            .map(|value| project_file_model(value, e))
            .transpose()?;
        let desired = if let Some(paths) = &e.paths {
            nix_me_codec::json::assert_paths_absent(model, &paths.sensitive)?;
            let mut probe = current_full
                .clone()
                .unwrap_or_else(|| Value::Object(Map::new()));
            nix_me_codec::json::merge_allowlisted(&mut probe, model, &paths.allow)?;
            model.clone()
        } else if e.merge == Merge::DeepMerge {
            let mut merged = current.clone().unwrap_or_else(|| Value::Object(Map::new()));
            crate::model::deep_merge(&mut merged, model);
            merged
        } else {
            model.clone()
        };
        let unchanged = if let (Some(paths), Some(current_full)) = (&e.paths, &current_full) {
            nix_me_codec::json::assert_semantic_readback(current_full, &desired, &paths.allow)
                .is_ok()
        } else {
            current.as_ref() == Some(&desired)
        };
        if unchanged {
            return Ok(());
        }
        let state_entry = self
            .state
            .apps
            .get(&recipe.id)
            .and_then(|a| a.entries.get(&plan.bind));
        if path.exists() {
            let current_sum = checksum(&fs::read(&path)?);
            if state_entry.and_then(|s| s.checksum.as_ref()) != Some(&current_sum) {
                plan.drift.push(Drift {
                    target: path.display().to_string(),
                    reason: "out_of_band".into(),
                    detail: "file changed since last apply".into(),
                });
            }
        }
        plan.actions.push(Action {
            op: if e.paths.is_some() || e.merge == Merge::DeepMerge {
                "merge_file"
            } else {
                "replace_file"
            }
            .into(),
            target: path.display().to_string(),
            current,
            desired: Some(desired),
            value_type: Some(format_name(e.format).into()),
            result: None,
            error: None,
        });
        Ok(())
    }
    fn plan_command(
        &mut self,
        e: &CommandEntry,
        model: &Value,
        plan: &mut EntryPlan,
    ) -> Result<()> {
        let desired = model
            .as_array()
            .ok_or_else(|| anyhow!("command bind {} must be a list of strings", e.name))?
            .iter()
            .map(|v| {
                v.as_str()
                    .map(str::to_owned)
                    .ok_or_else(|| anyhow!("command bind {} contains a non-string", e.name))
            })
            .collect::<Result<BTreeSet<_>>>()?;
        let output = self.runner.run(&e.list.get)?;
        let current = output
            .lines()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(str::to_owned)
            .collect::<BTreeSet<_>>();
        for item in desired.difference(&current) {
            plan.actions.push(Action {
                op: "add".into(),
                target: item.clone(),
                current: None,
                desired: Some(Value::String(item.clone())),
                value_type: Some("string".into()),
                result: None,
                error: None,
            });
        }
        for item in current.difference(&desired) {
            if e.converges == Converges::AddOnly || e.list.del.is_none() {
                plan.drift.push(Drift {
                    target: item.clone(),
                    reason: "add_only".into(),
                    detail: "command set cannot delete this member".into(),
                });
            } else {
                plan.actions.push(Action {
                    op: "del".into(),
                    target: item.clone(),
                    current: Some(Value::String(item.clone())),
                    desired: None,
                    value_type: Some("string".into()),
                    result: None,
                    error: None,
                });
            }
        }
        Ok(())
    }

    fn plan_command_value(
        &mut self,
        entry: &CommandValueEntry,
        desired: &Value,
        plan: &mut EntryPlan,
    ) -> Result<()> {
        if !validate_value_type(desired, entry.value_type) {
            bail!(
                "command_value bind {} must be {}",
                entry.name,
                entry.value_type.as_str()
            );
        }
        let current = parse_command_value(
            &self
                .runner
                .run_owned(&entry.get.executable, &entry.get.arguments)?,
            entry.value_type,
        )
        .with_context(|| format!("parse command_value {} read-back", entry.name))?;
        if equal_typed(Some(&current), desired, entry.value_type) {
            return Ok(());
        }
        plan.actions.push(Action {
            op: "set_command_value".into(),
            target: command_value_set_display(entry, desired)?,
            current: Some(current),
            desired: Some(desired.clone()),
            value_type: Some(entry.value_type.as_str().into()),
            result: None,
            error: None,
        });
        Ok(())
    }

    fn plan_accessibility(
        &mut self,
        recipe: &Recipe,
        entry: &AccessibilityEntry,
        model: &Value,
        plan: &mut EntryPlan,
    ) -> Result<()> {
        let transition = crate::accessibility::transition(entry, model)?;
        let current = crate::accessibility::inspect_for_plan(
            self.runner,
            &recipe.bundle_id,
            entry,
            self.options.no_exec,
            &transition.expected,
        )?;
        if let Some(action) =
            crate::accessibility::plan_action(&recipe.bundle_id, entry, &transition, current)
                .with_context(|| {
                    format!(
                        "{} Accessibility control {} failed its expected-state gate",
                        recipe.name, entry.name
                    )
                })?
        {
            plan.actions.push(action);
        }
        Ok(())
    }
    fn plan_import(
        &mut self,
        recipe: &Recipe,
        e: &GeneratedImportEntry,
        model: &Value,
        plan: &mut EntryPlan,
        checklist: &mut Vec<ChecklistItem>,
    ) -> Result<()> {
        let desired_sum = checksum(&serde_json::to_vec(model)?);
        let previous = self
            .state
            .apps
            .get(&recipe.id)
            .and_then(|a| a.entries.get(&plan.bind))
            .and_then(|e| e.checksum.as_ref());
        if previous != Some(&desired_sum) {
            let target = self.state_dir.join("artifacts").join(format!(
                "{}-{}.artifact",
                recipe.id,
                sanitize(&plan.bind)
            ));
            plan.actions.push(Action {
                op: "materialize".into(),
                target: target.display().to_string(),
                current: previous.map(|v| Value::String(v.clone())),
                desired: Some(model.clone()),
                value_type: Some("artifact".into()),
                result: None,
                error: None,
            });
            plan.actions.push(Action {
                op: "deliver".into(),
                target: e.deliver.replace(
                    "{artifact}",
                    &shell_words::quote(&target.display().to_string()),
                ),
                current: None,
                desired: None,
                value_type: None,
                result: None,
                error: None,
            });
        }
        if e.confirm != Confirm::None {
            checklist.push(ChecklistItem {
                app: recipe.id.clone(),
                step: format!("Confirm import for {}", recipe.name),
                confirm: confirm_name(e.confirm),
                satisfied: false,
            });
        }
        Ok(())
    }
    fn plan_manual(
        &mut self,
        recipe: &Recipe,
        e: &ManualEntry,
        checklist: &mut Vec<ChecklistItem>,
    ) -> Result<()> {
        let satisfied = self.marker_satisfied(e.marker.as_ref())?;
        checklist.push(ChecklistItem {
            app: recipe.id.clone(),
            step: e.step.clone(),
            confirm: confirm_name(e.confirm),
            satisfied,
        });
        Ok(())
    }
    fn marker_satisfied(&mut self, marker: Option<&serde_yaml::Value>) -> Result<bool> {
        let Some(marker) = marker else {
            return Ok(false);
        };
        let value = serde_json::to_value(marker)?;
        if value.is_null() {
            return Ok(false);
        };
        if let Some(d) = value.get("defaults_key") {
            return Ok(self
                .prefs
                .read(
                    d["domain"].as_str().unwrap_or(""),
                    d["key"].as_str().unwrap_or(""),
                    Host::Any,
                )?
                .is_some());
        }
        if let Some(path) = value.get("file_exists").and_then(|v| v.as_str()) {
            return Ok(expand_home(path)?.exists());
        }
        if let Some(cmd) = value.get("command").and_then(|v| v.as_str()) {
            return Ok(self.runner.succeeds(cmd));
        }
        Ok(false)
    }

    pub fn apply(
        &mut self,
        recipes: &[Recipe],
        values: &Map<String, Value>,
        mut plan: Plan,
    ) -> Plan {
        let state_before = self.state.clone();
        let mut failure = None;
        let mut journal = Vec::new();
        let mut touched_domains = BTreeSet::new();
        let mut touched_apps = BTreeSet::new();
        let mut deferred_delivery: Option<(String, String, String)> = None;
        let mut delivery_failure_unverified = false;
        let profile = Value::Object(values.clone());
        let delivery_count = plan
            .apps
            .iter()
            .flat_map(|app| &app.entries)
            .flat_map(|entry| &entry.actions)
            .filter(|action| action.op == "deliver")
            .count();
        if delivery_count > 1 {
            failure = Some(
                "multiple generated_import deliveries cannot share one transaction without independent rollback contracts"
                    .to_owned(),
            );
        }
        'apply: for app_plan in &mut plan.apps {
            if failure.is_some() {
                break;
            }
            let Some(recipe) = recipes.iter().find(|r| r.id == app_plan.id) else {
                continue;
            };
            let app_values = values.get(&recipe.id).unwrap();
            let models = match self.bind_models(recipe, app_values, values) {
                Ok(v) => v,
                Err(e) => {
                    failure = Some(format!("bind {} before apply: {e:#}", recipe.id));
                    break 'apply;
                }
            };
            for (index, entry_plan) in app_plan.entries.iter_mut().enumerate() {
                let entry = &recipe.config[index];
                let out_of_band = entry_plan.drift.iter().any(|d| d.reason == "out_of_band");
                if out_of_band && self.options.force {
                    entry_plan.drift.retain(|d| d.reason != "out_of_band");
                }
                for action in &mut entry_plan.actions {
                    if action.op == "deliver" {
                        let model = models[index]
                            .as_ref()
                            .ok_or_else(|| anyhow!("generated import has no bound model"));
                        match model {
                            Ok(_) => {
                                deferred_delivery = Some((
                                    recipe.id.clone(),
                                    entry_plan.bind.clone(),
                                    action.target.clone(),
                                ));
                            }
                            Err(error) => {
                                action.result = Some("failed".into());
                                action.error = Some(error.to_string());
                                failure = Some(error.to_string());
                                break 'apply;
                            }
                        }
                        continue;
                    }
                    if out_of_band && !self.options.force {
                        let error = "out-of-band file drift; rerun with --force".to_owned();
                        action.result = Some("failed".into());
                        action.error = Some(error.clone());
                        failure = Some(error);
                        break 'apply;
                    }
                    let undo = match self.prepare_undo(recipe, entry, action, &models[index]) {
                        Ok(undo) => undo,
                        Err(error) => {
                            action.result = Some("failed".into());
                            action.error = Some(error.to_string());
                            failure = Some(format!("prepare transaction rollback: {error:#}"));
                            break 'apply;
                        }
                    };
                    journal.push(undo);
                    touched_apps.insert(recipe.id.clone());
                    if let Err(error) = self.execute_action(
                        recipe,
                        entry,
                        action,
                        &models[index],
                        &profile,
                        &mut touched_domains,
                    ) {
                        action.result = Some("failed".into());
                        action.error = Some(error.to_string());
                        failure = Some(format!(
                            "apply {}.{}: {error:#}",
                            recipe.id, entry_plan.bind
                        ));
                        break 'apply;
                    }
                    action.result = Some("ok".into());
                }
                let all_ok = entry_plan
                    .actions
                    .iter()
                    .all(|a| a.result.as_deref() == Some("ok"))
                    || entry_plan.actions.is_empty();
                if all_ok && !entry_plan.actions.is_empty() {
                    let app = self.state.apps.entry(recipe.id.clone()).or_default();
                    let ent = app.entries.entry(entry_plan.bind.clone()).or_default();
                    ent.applied_at = self.clock.now();
                    match entry {
                        ConfigEntry::Defaults(_) => ent.last_applied = models[index].clone(),
                        ConfigEntry::CommandValue(_) => ent.last_applied = models[index].clone(),
                        ConfigEntry::Accessibility(_) => ent.last_applied = models[index].clone(),
                        ConfigEntry::File(_) => {
                            if let Some(path) =
                                entry_plan.actions.first().map(|a| PathBuf::from(&a.target))
                            {
                                if let Ok(bytes) = fs::read(path) {
                                    ent.checksum = Some(checksum(&bytes));
                                }
                            }
                        }
                        ConfigEntry::GeneratedImport(_) => {
                            ent.checksum = Some(checksum(
                                &serde_json::to_vec(models[index].as_ref().unwrap()).unwrap(),
                            ))
                        }
                        _ => {}
                    }
                }
            }
        }

        if failure.is_none() {
            for domain in &touched_domains {
                if let Err(error) = self.prefs.synchronize(domain) {
                    failure = Some(format!("synchronize defaults domain {domain}: {error:#}"));
                    break;
                }
            }
        }
        let commands = touched_apps
            .iter()
            .filter_map(|id| recipes.iter().find(|recipe| &recipe.id == id))
            .filter_map(poke_command)
            .collect::<BTreeSet<_>>();
        if failure.is_none() {
            for command in &commands {
                if let Err(error) = self.runner.run(command) {
                    failure = Some(format!("post-apply reload failed: {error:#}"));
                    break;
                }
            }
        }

        if failure.is_none() {
            if let Some((app_id, bind, command)) = &deferred_delivery {
                match self.runner.run(command) {
                    Ok(_) => {
                        if let Some(action) = plan
                            .apps
                            .iter_mut()
                            .find(|app| &app.id == app_id)
                            .and_then(|app| {
                                app.entries.iter_mut().find(|entry| &entry.bind == bind)
                            })
                            .and_then(|entry| {
                                entry.actions.iter_mut().find(|action| {
                                    action.op == "deliver" && &action.target == command
                                })
                            })
                        {
                            // Dispatch is not semantic verification. Keep the import
                            // retryable until a recipe can prove application state.
                            action.result = Some("delivery_requested".into());
                        }
                    }
                    Err(error) => {
                        delivery_failure_unverified = true;
                        failure = Some(format!(
                            "generated_import delivery failed without semantic read-back: {error:#}"
                        ));
                        if let Some(action) = plan
                            .apps
                            .iter_mut()
                            .find(|app| &app.id == app_id)
                            .and_then(|app| {
                                app.entries.iter_mut().find(|entry| &entry.bind == bind)
                            })
                            .and_then(|entry| {
                                entry.actions.iter_mut().find(|action| {
                                    action.op == "deliver" && &action.target == command
                                })
                            })
                        {
                            action.result = Some("failed".into());
                            action.error = failure.clone();
                        }
                    }
                }
            }
        }

        let failed = failure.is_some();
        if let Some(error) = failure.as_ref() {
            let rollback = self
                .rollback_transaction(&journal, &commands)
                .and_then(|_| {
                    if delivery_failure_unverified {
                        bail!("external generated_import delivery has no rollback read-back")
                    }
                    Ok(())
                });
            *self.state = state_before;
            mark_transaction_aborted(&mut plan, rollback.is_ok());
            match rollback {
                Ok(()) => self.warnings.push(format!(
                    "{error}; all completed mutations were rolled back and verified"
                )),
                Err(rollback_error) => self.warnings.push(format!(
                    "{error}; transaction rollback could not be proven: {rollback_error:#}"
                )),
            }
        }
        plan.mode = "apply".into();
        plan.recompute_summary_and_exit(true, failed);
        plan
    }

    fn prepare_undo(
        &mut self,
        recipe: &Recipe,
        entry: &ConfigEntry,
        action: &Action,
        model: &Option<Value>,
    ) -> Result<UndoAction> {
        match entry {
            ConfigEntry::Defaults(defaults) => {
                let key = action
                    .target
                    .strip_prefix(&format!("{}/", defaults.domain))
                    .ok_or_else(|| anyhow!("invalid defaults action target"))?;
                let schema = defaults.keys.get(key);
                let host = schema.map(|value| value.host).unwrap_or_default();
                let value_type = schema
                    .map(|value| value.value_type)
                    .or_else(|| {
                        action
                            .desired
                            .as_ref()
                            .and_then(|value| infer_type(value).ok())
                    })
                    .ok_or_else(|| anyhow!("defaults action has no typed desired value"))?;
                Ok(UndoAction::Defaults {
                    domain: defaults.domain.clone(),
                    key: key.to_owned(),
                    host,
                    value_type,
                    previous: self.prefs.read(&defaults.domain, key, host)?,
                })
            }
            ConfigEntry::File(_) | ConfigEntry::GeneratedImport(_) if action.op != "deliver" => {
                let path = PathBuf::from(&action.target);
                let metadata = safe_regular_file_metadata(&path)?;
                Ok(UndoAction::File {
                    previous: metadata.as_ref().map(|_| fs::read(&path)).transpose()?,
                    mode: metadata.map(|value| value.permissions().mode() & 0o7777),
                    path,
                })
            }
            ConfigEntry::Command(command) => {
                let previous = command_set(self.runner, command)?;
                if command.list.del.is_none() {
                    bail!(
                        "command entry {} has no delete operation and cannot participate in a transaction",
                        command.name
                    );
                }
                Ok(UndoAction::CommandSet {
                    entry: command.clone(),
                    previous,
                })
            }
            ConfigEntry::CommandValue(command) => {
                let output = self
                    .runner
                    .run_owned(&command.get.executable, &command.get.arguments)?;
                Ok(UndoAction::CommandValue {
                    entry: command.clone(),
                    previous: parse_command_value(&output, command.value_type)?,
                })
            }
            ConfigEntry::Accessibility(accessibility) => {
                let transition = crate::accessibility::transition(
                    accessibility,
                    model
                        .as_ref()
                        .ok_or_else(|| anyhow!("Accessibility action has no transition model"))?,
                )?;
                let current =
                    crate::accessibility::inspect(self.runner, &recipe.bundle_id, accessibility)?;
                if current != transition.expected {
                    bail!("Accessibility state changed after planning; refusing mutation");
                }
                Ok(UndoAction::Accessibility {
                    bundle_id: recipe.bundle_id.clone(),
                    entry: accessibility.clone(),
                    previous: transition.expected,
                    applied: transition.desired,
                })
            }
            ConfigEntry::File(_) => bail!("file action has an unsupported transactional operation"),
            ConfigEntry::Manual(_) | ConfigEntry::GeneratedImport(_) => Ok(UndoAction::None),
        }
    }

    fn rollback_transaction(
        &mut self,
        journal: &[UndoAction],
        pokes: &BTreeSet<String>,
    ) -> Result<()> {
        let mut errors = Vec::new();
        for undo in journal.iter().rev() {
            if let Err(error) = self.rollback_one(undo) {
                errors.push(format!("{error:#}"));
            }
        }
        for command in pokes {
            if let Err(error) = self.runner.run(command) {
                errors.push(format!("reload restored application state: {error:#}"));
            }
        }
        if errors.is_empty() {
            Ok(())
        } else {
            bail!(errors.join("; "))
        }
    }

    fn rollback_one(&mut self, undo: &UndoAction) -> Result<()> {
        match undo {
            UndoAction::Defaults {
                domain,
                key,
                host,
                value_type,
                previous,
            } => {
                match previous {
                    Some(value) => {
                        self.prefs
                            .write_typed(domain, key, value, *host, *value_type)?
                    }
                    None => self.prefs.delete(domain, key, *host)?,
                }
                let readback = self.prefs.read(domain, key, *host)?;
                if readback != *previous {
                    bail!("defaults rollback read-back differs for {domain}/{key}");
                }
                self.prefs.synchronize(domain)?;
                Ok(())
            }
            UndoAction::File {
                path,
                previous,
                mode,
            } => {
                match previous {
                    Some(bytes) => {
                        write_bytes_atomic(path, bytes, &format!("0{:o}", mode.unwrap_or(0o600)))?
                    }
                    None => match fs::remove_file(path) {
                        Ok(()) => {}
                        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
                        Err(error) => return Err(error.into()),
                    },
                }
                verify_file_rollback(path, previous.as_deref(), *mode)
            }
            UndoAction::CommandSet { entry, previous } => {
                self.restore_command_set(entry, previous)?;
                let readback = command_set(self.runner, entry)?;
                if &readback != previous {
                    bail!("command set rollback read-back differs for {}", entry.name);
                }
                Ok(())
            }
            UndoAction::CommandValue { entry, previous } => {
                let arguments = command_value_set_arguments(entry, previous)?;
                self.run_owned_with_retries(&entry.set.executable, &arguments)?;
                verify_command_value(self.runner, entry, previous)
            }
            UndoAction::Accessibility {
                bundle_id,
                entry,
                previous,
                applied,
            } => {
                let current = crate::accessibility::inspect(self.runner, bundle_id, entry)?;
                if current == *previous {
                    return Ok(());
                }
                if current != *applied {
                    bail!("Accessibility rollback found an unexpected intermediate value");
                }
                crate::accessibility::apply(
                    self.runner,
                    bundle_id,
                    entry,
                    &crate::accessibility::AccessibilityTransition {
                        expected: applied.clone(),
                        desired: previous.clone(),
                    },
                )?;
                let readback = crate::accessibility::inspect(self.runner, bundle_id, entry)?;
                if readback != *previous {
                    bail!("Accessibility rollback read-back differs from original value");
                }
                Ok(())
            }
            UndoAction::None => Ok(()),
        }
    }

    fn restore_command_set(
        &mut self,
        entry: &CommandEntry,
        previous: &BTreeSet<String>,
    ) -> Result<()> {
        let current = command_set(self.runner, entry)?;
        for item in current.difference(previous) {
            let action = Action {
                op: "del".into(),
                target: item.clone(),
                current: Some(Value::String(item.clone())),
                desired: None,
                value_type: Some("string".into()),
                result: None,
                error: None,
            };
            self.run_command_with_retries(&command_action_command(entry, &action)?)?;
        }
        for item in previous.difference(&current) {
            let action = Action {
                op: "add".into(),
                target: item.clone(),
                current: None,
                desired: Some(Value::String(item.clone())),
                value_type: Some("string".into()),
                result: None,
                error: None,
            };
            self.run_command_with_retries(&command_action_command(entry, &action)?)?;
        }
        Ok(())
    }

    fn execute_action(
        &mut self,
        recipe: &Recipe,
        entry: &ConfigEntry,
        action: &Action,
        model: &Option<Value>,
        profile: &Value,
        domains: &mut BTreeSet<String>,
    ) -> Result<()> {
        match entry {
            ConfigEntry::Defaults(e) => {
                if action.op != "write" {
                    return Ok(());
                }
                let key = action
                    .target
                    .strip_prefix(&format!("{}/", e.domain))
                    .ok_or_else(|| anyhow!("invalid defaults action target"))?;
                let host = e.keys.get(key).map(|s| s.host).unwrap_or_default();
                let ty = e
                    .keys
                    .get(key)
                    .map(|s| s.value_type)
                    .unwrap_or_else(|| infer_type(action.desired.as_ref().unwrap()).unwrap());
                self.prefs.write_typed(
                    &e.domain,
                    key,
                    action.desired.as_ref().unwrap(),
                    host,
                    ty,
                )?;
                let readback = self.prefs.read(&e.domain, key, host)?;
                if !equal_typed(readback.as_ref(), action.desired.as_ref().unwrap(), ty) {
                    bail!(
                        "defaults semantic read-back differs for {}/{}",
                        e.domain,
                        key
                    );
                }
                domains.insert(e.domain.clone());
                Ok(())
            }
            ConfigEntry::File(e) => {
                let path = PathBuf::from(&action.target);
                write_file_atomic_verified(
                    recipe,
                    &path,
                    e,
                    action.desired.as_ref().unwrap(),
                    self.runner,
                )
            }
            ConfigEntry::Command(e) => {
                self.run_command_with_retries(&command_action_command(e, action)?)?;
                let set = command_set(self.runner, e)?;
                let present = set.contains(&action.target);
                if (action.op == "add" && !present) || (action.op == "del" && present) {
                    bail!("command set semantic read-back differs for {}", e.name);
                }
                Ok(())
            }
            ConfigEntry::CommandValue(e) => {
                let desired = action
                    .desired
                    .as_ref()
                    .ok_or_else(|| anyhow!("command_value action is missing a desired value"))?;
                let arguments = command_value_set_arguments(e, desired)?;
                self.run_owned_with_retries(&e.set.executable, &arguments)?;
                let verification = self
                    .runner
                    .run_owned(&e.get.executable, &e.get.arguments)
                    .and_then(|output| parse_command_value(&output, e.value_type))
                    .and_then(|readback| {
                        if equal_typed(Some(&readback), desired, e.value_type) {
                            Ok(())
                        } else {
                            bail!(
                                "command_value {} semantic read-back differs from requested value",
                                e.name
                            )
                        }
                    });
                if let Err(error) = verification {
                    return Err(error).context("command_value semantic verification failed");
                }
                Ok(())
            }
            ConfigEntry::Accessibility(e) => {
                verify_recipe_version(recipe, self.runner, false)?;
                verify_accessibility_permission(recipe)?;
                let transition = crate::accessibility::transition(
                    e,
                    model.as_ref().ok_or_else(|| {
                        anyhow!("Accessibility action is missing its transition model")
                    })?,
                )?;
                if action.current.as_ref() != Some(&transition.expected)
                    || action.desired.as_ref() != Some(&transition.desired)
                {
                    bail!("Accessibility plan does not match the configured typed transition");
                }
                crate::accessibility::apply(self.runner, &recipe.bundle_id, e, &transition)
            }
            ConfigEntry::GeneratedImport(e) => {
                if action.op == "deliver" {
                    return self.runner.run(&action.target).map(|_| ());
                }
                if action.op != "materialize" {
                    return Ok(());
                }
                let model = model.as_ref().unwrap();
                let app_state = self.state.apps.entry(recipe.id.clone()).or_default();
                let artifact_state = app_state
                    .artifact_state
                    .get_or_insert_with(ArtifactState::default);
                let bytes = match &e.artifact {
                    Artifact::Pipeline { pipeline } => {
                        crate::pipeline::encode(pipeline, model, profile, artifact_state)?
                    }
                    Artifact::Codec {
                        codec,
                        codec_version,
                    } => nix_me_codec::builtin_registry().encode(codec, codec_version, model)?,
                };
                let path = PathBuf::from(&action.target);
                if let Some(parent) = path.parent() {
                    fs::create_dir_all(parent)?;
                }
                write_bytes_atomic(&path, &bytes, "0600")?;
                Ok(())
            }
            ConfigEntry::Manual(_) => Ok(()),
        }
    }
    fn run_command_with_retries(&mut self, command: &str) -> Result<()> {
        let mut last = None;
        for _ in 0..3 {
            match self.runner.run(command) {
                Ok(_) => return Ok(()),
                Err(error) => last = Some(error),
            }
        }
        Err(last.unwrap()).with_context(|| format!("command failed after 3 attempts: {command}"))
    }

    fn run_owned_with_retries(&mut self, program: &str, arguments: &[String]) -> Result<()> {
        let mut last = None;
        for _ in 0..3 {
            match self.runner.run_owned(program, arguments) {
                Ok(_) => return Ok(()),
                Err(error) => last = Some(error),
            }
        }
        Err(last.unwrap()).with_context(|| {
            format!(
                "owned command failed after 3 attempts: {}",
                render_owned_command(program, arguments)
            )
        })
    }
}

fn command_set<R: CommandRunner>(runner: &mut R, entry: &CommandEntry) -> Result<BTreeSet<String>> {
    Ok(runner
        .run(&entry.list.get)?
        .lines()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
        .collect())
}

fn mark_transaction_aborted(plan: &mut Plan, rollback_verified: bool) {
    for action in plan
        .apps
        .iter_mut()
        .flat_map(|app| &mut app.entries)
        .flat_map(|entry| &mut entry.actions)
    {
        match action.result.as_deref() {
            Some("ok") => {
                action.result = Some(if rollback_verified {
                    "rolled_back".into()
                } else {
                    "rollback_unverified".into()
                });
                action.error = Some(if rollback_verified {
                    "transaction aborted; original state restored and verified".into()
                } else {
                    "transaction aborted; rollback could not be fully verified".into()
                });
            }
            None => {
                action.result = Some("skipped".into());
                action.error = Some("transaction stopped after an earlier failure".into());
            }
            _ => {}
        }
    }
}

pub fn verify_recipe_version<R: CommandRunner>(
    recipe: &Recipe,
    runner: &mut R,
    dry_run: bool,
) -> Result<()> {
    let Some(version) = &recipe.app_version else {
        return Ok(());
    };
    let output = match version.source {
        Some(AppVersionSource::BundleShortVersion) => read_bundle_short_version(recipe)?,
        None => {
            let command = version.command.as_deref().ok_or_else(|| {
                anyhow!("{} version preflight has no configured source", recipe.name)
            })?;
            let output = runner
                .run(command)
                .with_context(|| format!("{} version preflight failed", recipe.name))?;
            if dry_run {
                return Ok(());
            }
            output
        }
    };
    nix_me_codec::version::require_supported(
        &output,
        &version.supported_exact,
        &version.supported_majors,
    )
    .with_context(|| format!("{} version preflight failed", recipe.name))
}

fn read_bundle_short_version(recipe: &Recipe) -> Result<String> {
    let app_path = recipe
        .detect
        .as_ref()
        .and_then(|detect| detect.app_path.as_deref())
        .ok_or_else(|| anyhow!("{} has no application bundle path", recipe.name))?;
    let app_path = Path::new(app_path);
    if app_path.parent() != Some(Path::new("/Applications"))
        || app_path.extension().and_then(|value| value.to_str()) != Some("app")
    {
        bail!(
            "{} bundle version source is outside direct /Applications confinement",
            recipe.name
        );
    }

    let applications = fs::canonicalize("/Applications")?;
    reject_unsafe_bundle_metadata(app_path, true)?;
    let canonical_app = fs::canonicalize(app_path)?;
    if canonical_app.parent() != Some(applications.as_path()) {
        bail!("{} application bundle escapes /Applications", recipe.name);
    }

    let contents = app_path.join("Contents");
    let info = contents.join("Info.plist");
    reject_unsafe_bundle_metadata(&contents, true)?;
    reject_unsafe_bundle_metadata(&info, false)?;
    let canonical_info = fs::canonicalize(&info)?;
    if !canonical_info.starts_with(&canonical_app) {
        bail!("{} Info.plist escapes its application bundle", recipe.name);
    }

    let value = plist::Value::from_file(&info)
        .with_context(|| format!("read confined bundle metadata {}", info.display()))?;
    value
        .as_dictionary()
        .and_then(|dictionary| dictionary.get("CFBundleShortVersionString"))
        .and_then(plist::Value::as_string)
        .map(str::to_owned)
        .ok_or_else(|| {
            anyhow!(
                "{} bundle has no string CFBundleShortVersionString",
                recipe.name
            )
        })
}

fn reject_unsafe_bundle_metadata(path: &Path, directory: bool) -> Result<()> {
    let metadata = fs::symlink_metadata(path)
        .with_context(|| format!("read bundle metadata {}", path.display()))?;
    if metadata.file_type().is_symlink() {
        bail!("bundle metadata path is a symlink: {}", path.display());
    }
    if directory && !metadata.is_dir() {
        bail!(
            "bundle metadata path is not a directory: {}",
            path.display()
        );
    }
    if !directory && !metadata.is_file() {
        bail!(
            "bundle metadata path is not a regular file: {}",
            path.display()
        );
    }
    if metadata.permissions().mode() & 0o022 != 0 {
        bail!(
            "bundle metadata path is group/world writable: {}",
            path.display()
        );
    }
    if !directory && metadata.nlink() != 1 {
        bail!(
            "bundle metadata file has an unsafe link count: {}",
            path.display()
        );
    }
    if !directory && metadata.len() > 4 * 1024 * 1024 {
        bail!(
            "bundle metadata file exceeds the safe size limit: {}",
            path.display()
        );
    }
    Ok(())
}

#[cfg(target_os = "macos")]
pub fn verify_accessibility_permission(recipe: &Recipe) -> Result<()> {
    if mac_permissions::accessibility_granted() {
        Ok(())
    } else {
        bail!(
            "{} requires Accessibility: System Settings > Privacy & Security > Accessibility",
            recipe.name
        )
    }
}

#[cfg(not(target_os = "macos"))]
pub fn verify_accessibility_permission(recipe: &Recipe) -> Result<()> {
    bail!("{} Accessibility actions require macOS", recipe.name)
}

pub fn recipe_is_installed<R: CommandRunner>(recipe: &Recipe, runner: &mut R) -> bool {
    let Some(detection) = &recipe.detect else {
        return true;
    };
    if let Some(path) = &detection.app_path {
        if Path::new(path).exists() {
            return true;
        }
    }
    if let Some(command) = &detection.command {
        return runner.succeeds(command);
    }
    detection.app_path.is_none()
}

#[cfg(target_os = "macos")]
mod mac_permissions {
    #[link(name = "ApplicationServices", kind = "framework")]
    extern "C" {
        fn AXIsProcessTrusted() -> u8;
    }

    #[link(name = "CoreGraphics", kind = "framework")]
    extern "C" {
        fn CGPreflightListenEventAccess() -> bool;
        fn CGPreflightScreenCaptureAccess() -> bool;
    }

    pub fn accessibility_granted() -> bool {
        unsafe { AXIsProcessTrusted() != 0 }
    }

    pub fn input_monitoring_granted() -> bool {
        unsafe { CGPreflightListenEventAccess() }
    }

    pub fn screen_recording_granted() -> bool {
        unsafe { CGPreflightScreenCaptureAccess() }
    }
}

pub fn command_action_command(entry: &CommandEntry, action: &Action) -> Result<String> {
    let template = if action.op == "add" {
        &entry.list.add
    } else {
        entry
            .list
            .del
            .as_ref()
            .ok_or_else(|| anyhow!("delete command absent"))?
    };
    Ok(template.replace("{item}", &shell_words::quote(&action.target)))
}

pub fn poke_command(recipe: &Recipe) -> Option<String> {
    match recipe.apply.poke {
        Poke::None => None,
        Poke::Cfprefsd => Some("killall cfprefsd".into()),
        Poke::RestartApp => Some(format!(
            "osascript -e 'tell application \"{}\" to quit' >/dev/null 2>&1 || true; open -a {}",
            recipe.name.replace('\\', "\\\\").replace('"', "\\\""),
            shell_words::quote(&recipe.name)
        )),
        Poke::Script => recipe.apply.poke_script.clone(),
    }
}

fn lookup_source<'a>(all: &'a Map<String, Value>, source: &str) -> Option<&'a Value> {
    let mut parts = source.split('.');
    if parts.next()? != "profile" {
        return None;
    }
    let mut current = all.get(parts.next()?)?;
    for part in parts {
        current = current.get(part)?;
    }
    Some(current)
}
fn infer_type(value: &Value) -> Result<ValueType> {
    Ok(match value {
        Value::Bool(_) => ValueType::Bool,
        Value::Number(n) if n.as_i64().is_some() || n.as_u64().is_some() => ValueType::Int,
        Value::Number(_) => ValueType::Float,
        Value::String(_) => ValueType::String,
        Value::Array(_) => ValueType::Array,
        Value::Object(_) => ValueType::Dict,
        Value::Null => bail!("null is not a preference value"),
    })
}
fn is_rfc3339(value: &str) -> bool {
    plist::Date::from_xml_format(value).is_ok()
}
fn coerce(value: &Value, ty: ValueType) -> Result<Value> {
    if ty == ValueType::Float {
        if let Some(v) = value.as_f64() {
            return Ok(Value::Number(serde_json::Number::from_f64(v).unwrap()));
        }
    }
    Ok(value.clone())
}
fn equal_typed(current: Option<&Value>, desired: &Value, ty: ValueType) -> bool {
    match (current, ty) {
        (Some(c), ValueType::Float) => match (c.as_f64(), desired.as_f64()) {
            (Some(a), Some(b)) => (a - b).abs() <= f64::EPSILON.max(1e-6 * a.abs().max(b.abs())),
            _ => false,
        },
        (Some(c), _) => c == desired,
        _ => false,
    }
}
fn home_dir() -> Result<PathBuf> {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .ok_or_else(|| anyhow!("HOME is not set"))
}
fn expand_home(path: &str) -> Result<PathBuf> {
    if path == "~" {
        home_dir()
    } else if let Some(rest) = path.strip_prefix("~/") {
        Ok(home_dir()?.join(rest))
    } else {
        Ok(PathBuf::from(path))
    }
}
pub(crate) fn resolve_file_path(recipe: &Recipe, path: &str) -> Result<PathBuf> {
    if recipe.sandboxed {
        let relative = Path::new(path);
        if relative.is_absolute()
            || path == "~"
            || path.starts_with("~/")
            || relative
                .components()
                .any(|component| !matches!(component, std::path::Component::Normal(_)))
        {
            bail!(
                "sandboxed file path must be relative and cannot contain '.', '..', '~', or a root"
            );
        }
        let root = home_dir()?
            .join("Library/Containers")
            .join(&recipe.bundle_id)
            .join("Data");
        let target = root.join(relative);
        validate_sandbox_target(&root, &target)?;
        Ok(target)
    } else {
        expand_home(path)
    }
}

fn validate_sandbox_target(root: &Path, target: &Path) -> Result<()> {
    let relative = target
        .strip_prefix(root)
        .map_err(|_| anyhow!("sandboxed path escapes its container root"))?;
    if relative
        .components()
        .any(|component| !matches!(component, std::path::Component::Normal(_)))
    {
        bail!("sandboxed path is not normalized beneath its container root");
    }
    reject_symlink_component(root)?;
    let mut current = root.to_path_buf();
    for component in relative.components() {
        current.push(component.as_os_str());
        reject_symlink_component(&current)?;
    }
    if root.exists() {
        let canonical_root = fs::canonicalize(root)
            .with_context(|| format!("canonicalize sandbox root {}", root.display()))?;
        let mut existing = target;
        while !existing.exists() {
            existing = existing
                .parent()
                .ok_or_else(|| anyhow!("sandboxed path has no existing ancestor"))?;
        }
        let canonical_existing = fs::canonicalize(existing).with_context(|| {
            format!("canonicalize sandbox path ancestor {}", existing.display())
        })?;
        if !canonical_existing.starts_with(&canonical_root) {
            bail!("sandboxed path escapes its canonical container root");
        }
    }
    Ok(())
}

fn reject_symlink_component(path: &Path) -> Result<()> {
    match fs::symlink_metadata(path) {
        Ok(metadata) if metadata.file_type().is_symlink() => {
            bail!(
                "sandboxed path contains a symlink component: {}",
                path.display()
            )
        }
        Ok(_) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error).with_context(|| format!("inspect path {}", path.display())),
    }
}

fn safe_regular_file_metadata(path: &Path) -> Result<Option<fs::Metadata>> {
    let metadata = match fs::symlink_metadata(path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => {
            return Err(error).with_context(|| format!("inspect file {}", path.display()))
        }
    };
    if metadata.file_type().is_symlink() {
        bail!("refusing a symlink settings file: {}", path.display());
    }
    if !metadata.is_file() {
        bail!("settings path is not a regular file: {}", path.display());
    }
    if metadata.nlink() != 1 {
        bail!(
            "refusing a settings file with an unsafe hard-link count: {}",
            path.display()
        );
    }
    Ok(Some(metadata))
}

fn safe_regular_file_read_path(path: &Path) -> Result<PathBuf> {
    safe_regular_file_read_path_in_store(path, Path::new("/nix/store"))
}

fn safe_regular_file_read_path_in_store(path: &Path, store_root: &Path) -> Result<PathBuf> {
    let metadata =
        fs::symlink_metadata(path).with_context(|| format!("inspect file {}", path.display()))?;
    if !metadata.file_type().is_symlink() {
        safe_regular_file_metadata(path)?;
        return Ok(path.to_path_buf());
    }

    let target = fs::canonicalize(path)
        .with_context(|| format!("resolve settings symlink {}", path.display()))?;
    let canonical_store = fs::canonicalize(store_root)
        .with_context(|| format!("resolve Nix store {}", store_root.display()))?;
    if target.strip_prefix(&canonical_store).is_err() {
        bail!(
            "refusing a settings symlink outside the Nix store: {} -> {}",
            path.display(),
            target.display()
        );
    }

    let target_metadata = fs::symlink_metadata(&target)
        .with_context(|| format!("inspect settings symlink target {}", target.display()))?;
    if !target_metadata.is_file() {
        bail!(
            "settings symlink target is not a regular file: {}",
            target.display()
        );
    }
    if target_metadata.permissions().mode() & 0o022 != 0 {
        bail!(
            "settings symlink target is group/world writable: {}",
            target.display()
        );
    }

    Ok(target)
}
fn validate_file_model(recipe: &Recipe, e: &FileEntry, model: &Value, bind: &str) -> Result<()> {
    let valid = if e.format == FileFormat::Text {
        model.is_string()
    } else {
        model.is_object()
    };
    if !valid {
        bail!(
            "{}: profile.{}.{} must be {}",
            recipe.source_path.display(),
            recipe.id,
            bind,
            if e.format == FileFormat::Text {
                "a string"
            } else {
                "a map"
            }
        );
    }
    Ok(())
}
fn format_name(f: FileFormat) -> &'static str {
    match f {
        FileFormat::Text => "text",
        FileFormat::Json => "json",
        FileFormat::Jsonc => "jsonc",
        FileFormat::Toml => "toml",
        FileFormat::Yaml => "yaml",
        FileFormat::Plist => "plist",
        FileFormat::Ini => "ini",
        FileFormat::KeyValue => "key_value",
        FileFormat::QsettingsXml => "qsettings_xml",
    }
}
pub(crate) fn read_structured(path: &Path, format: FileFormat) -> Result<Value> {
    let read_path = safe_regular_file_read_path(path)?;
    let bytes = fs::read(&read_path)?;
    Ok(match format {
        FileFormat::Text => Value::String(String::from_utf8(bytes)?),
        FileFormat::Json => serde_json::from_slice(&bytes)?,
        FileFormat::Jsonc => json5::from_str(&String::from_utf8(bytes)?)?,
        FileFormat::Yaml => {
            serde_json::to_value(serde_yaml::from_slice::<serde_yaml::Value>(&bytes)?)?
        }
        FileFormat::Toml => {
            serde_json::to_value(toml::from_str::<toml::Value>(&String::from_utf8(bytes)?)?)?
        }
        FileFormat::Plist => {
            crate::prefs::plist_to_json(&plist::Value::from_reader(std::io::Cursor::new(bytes))?)
        }
        FileFormat::Ini => {
            nix_me_codec::line::LineDocument::parse(nix_me_codec::line::LineFormat::Ini, &bytes)?
                .model()?
        }
        FileFormat::KeyValue => nix_me_codec::line::LineDocument::parse(
            nix_me_codec::line::LineFormat::KeyValue,
            &bytes,
        )?
        .model()?,
        FileFormat::QsettingsXml => {
            nix_me_codec::qsettings::QSettingsDocument::parse(&bytes)?.model()?
        }
    })
}
fn structured_bytes(format: FileFormat, value: &Value) -> Result<Vec<u8>> {
    Ok(match format {
        FileFormat::Text => value.as_str().unwrap().as_bytes().to_vec(),
        FileFormat::Json | FileFormat::Jsonc => {
            let mut v = serde_json::to_vec_pretty(value)?;
            v.push(b'\n');
            v
        }
        FileFormat::Yaml => serde_yaml::to_string(value)?.into_bytes(),
        FileFormat::Toml => toml::to_string_pretty(value)?.into_bytes(),
        FileFormat::Plist => {
            let mut v = Vec::new();
            plist::to_writer_xml(&mut v, &crate::prefs::json_to_plist(value)?)?;
            v
        }
        FileFormat::Ini | FileFormat::KeyValue | FileFormat::QsettingsXml => {
            bail!("line-oriented formats require an allowlisted round-trip document")
        }
    })
}
fn write_bytes_atomic(path: &Path, bytes: &[u8], mode: &str) -> Result<()> {
    let existing = safe_regular_file_metadata(path)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
        let metadata = fs::symlink_metadata(parent)
            .with_context(|| format!("inspect settings parent {}", parent.display()))?;
        if metadata.file_type().is_symlink() || !metadata.is_dir() {
            bail!(
                "settings parent is not a safe directory: {}",
                parent.display()
            );
        }
    }
    let parent = path.parent().unwrap_or(Path::new("."));
    let mut temp = tempfile::NamedTempFile::new_in(parent)?;
    temp.write_all(bytes)?;
    temp.as_file().sync_all()?;
    if existing.is_some() {
        preserve_file_metadata(path, temp.path())?;
    }
    let requested = u32::from_str_radix(mode.trim_start_matches('0'), 8)?;
    let permissions = existing
        .as_ref()
        .map(|metadata| requested & (metadata.permissions().mode() & 0o7777))
        .unwrap_or(requested);
    temp.as_file()
        .set_permissions(fs::Permissions::from_mode(permissions))?;
    temp.persist(path).map_err(|e| e.error)?;
    Ok(())
}

#[cfg(target_os = "macos")]
fn preserve_file_metadata(source: &Path, destination: &Path) -> Result<()> {
    use std::ffi::CString;
    use std::os::raw::{c_char, c_int, c_void};
    use std::os::unix::ffi::OsStrExt;

    type CopyfileState = *mut c_void;
    type CopyfileFlags = u32;
    const COPYFILE_ACL: CopyfileFlags = 1 << 0;
    const COPYFILE_XATTR: CopyfileFlags = 1 << 2;

    extern "C" {
        fn copyfile(
            from: *const c_char,
            to: *const c_char,
            state: CopyfileState,
            flags: CopyfileFlags,
        ) -> c_int;
    }

    let source = CString::new(source.as_os_str().as_bytes())?;
    let destination = CString::new(destination.as_os_str().as_bytes())?;
    // copyfile preserves ACLs and extended attributes without replacing data.
    let result = unsafe {
        copyfile(
            source.as_ptr(),
            destination.as_ptr(),
            std::ptr::null_mut(),
            COPYFILE_ACL | COPYFILE_XATTR,
        )
    };
    if result == 0 {
        Ok(())
    } else {
        Err(std::io::Error::last_os_error()).context("preserve file ACLs and extended attributes")
    }
}

#[cfg(not(target_os = "macos"))]
fn preserve_file_metadata(_source: &Path, _destination: &Path) -> Result<()> {
    Ok(())
}

fn project_file_model(value: &Value, entry: &FileEntry) -> Result<Value> {
    let Some(paths) = &entry.paths else {
        return Ok(value.clone());
    };
    let projected = nix_me_codec::json::project_paths(value, &paths.allow)?;
    nix_me_codec::json::assert_paths_absent(&projected, &paths.sensitive)?;
    Ok(projected)
}

pub(crate) fn read_file_owned(path: &Path, entry: &FileEntry) -> Result<Value> {
    project_file_model(&read_structured(path, entry.format)?, entry)
}

fn materialize_file_bytes(path: &Path, entry: &FileEntry, desired: &Value) -> Result<Vec<u8>> {
    let original = match safe_regular_file_metadata(path)? {
        Some(_) => fs::read(path)?,
        None => Vec::new(),
    };
    match entry.format {
        FileFormat::Ini | FileFormat::KeyValue => {
            let format = if entry.format == FileFormat::Ini {
                nix_me_codec::line::LineFormat::Ini
            } else {
                nix_me_codec::line::LineFormat::KeyValue
            };
            let mut document = nix_me_codec::line::LineDocument::parse(format, &original)?;
            let paths = entry.paths.as_ref().ok_or_else(|| {
                anyhow!("line-oriented formats require an explicit path allowlist")
            })?;
            nix_me_codec::json::assert_paths_absent(desired, &paths.sensitive)?;
            document.patch(desired, &paths.allow)?;
            Ok(document.render())
        }
        FileFormat::QsettingsXml => {
            let mut document = nix_me_codec::qsettings::QSettingsDocument::parse(&original)?;
            let paths = entry
                .paths
                .as_ref()
                .ok_or_else(|| anyhow!("QSettings XML requires an explicit path allowlist"))?;
            nix_me_codec::json::assert_paths_absent(desired, &paths.sensitive)?;
            document.patch(desired, &paths.allow)?;
            document.render()
        }
        _ if entry.paths.is_some() => {
            let paths = entry.paths.as_ref().unwrap();
            nix_me_codec::json::assert_paths_absent(desired, &paths.sensitive)?;
            let mut full = if original.is_empty() {
                Value::Object(Map::new())
            } else {
                read_structured(path, entry.format)?
            };
            nix_me_codec::json::merge_allowlisted(&mut full, desired, &paths.allow)?;
            structured_bytes(entry.format, &full)
        }
        _ => structured_bytes(entry.format, desired),
    }
}

fn write_file_atomic_verified<R: CommandRunner>(
    recipe: &Recipe,
    path: &Path,
    entry: &FileEntry,
    desired: &Value,
    runner: &mut R,
) -> Result<()> {
    if recipe.sandboxed {
        let root = home_dir()?
            .join("Library/Containers")
            .join(&recipe.bundle_id)
            .join("Data");
        validate_sandbox_target(&root, path)?;
    }
    let metadata = safe_regular_file_metadata(path)?;
    let original = metadata.as_ref().map(|_| fs::read(path)).transpose()?;
    let original_mode = metadata.map(|metadata| metadata.permissions().mode() & 0o7777);
    let bytes = materialize_file_bytes(path, entry, desired)?;

    if let Some(command) = &entry.checks.preflight {
        let parent = path.parent().unwrap_or(Path::new("."));
        fs::create_dir_all(parent)?;
        let mut candidate = tempfile::NamedTempFile::new_in(parent)?;
        candidate.write_all(&bytes)?;
        candidate.as_file().sync_all()?;
        let command = command.replace(
            "{file}",
            &shell_words::quote(&candidate.path().display().to_string()),
        );
        runner
            .run(&command)
            .with_context(|| format!("candidate preflight failed for {}", path.display()))?;
    }

    if recipe.sandboxed {
        let root = home_dir()?
            .join("Library/Containers")
            .join(&recipe.bundle_id)
            .join("Data");
        validate_sandbox_target(&root, path)?;
    }

    write_bytes_atomic(path, &bytes, &entry.mode)?;
    let verify = (|| -> Result<()> {
        let readback = read_structured(path, entry.format)?;
        if let Some(paths) = &entry.paths {
            nix_me_codec::json::assert_semantic_readback(&readback, desired, &paths.allow)?;
            nix_me_codec::json::assert_paths_absent(desired, &paths.sensitive)?;
        } else if readback != *desired {
            bail!("semantic read-back differs from requested model");
        }
        if let Some(command) = &entry.checks.verify {
            let command =
                command.replace("{path}", &shell_words::quote(&path.display().to_string()));
            runner.run(&command).with_context(|| {
                format!("post-write verification failed for {}", path.display())
            })?;
        }
        Ok(())
    })();
    if let Err(error) = verify {
        match original {
            Some(bytes) => {
                let mode = original_mode.unwrap_or(0o600);
                write_bytes_atomic(path, &bytes, &format!("0{mode:o}"))
                    .context("restore original file after verification failure")?;
                verify_file_rollback(path, Some(&bytes), Some(mode))?;
            }
            None => match fs::remove_file(path) {
                Ok(()) => {}
                Err(remove_error) if remove_error.kind() == std::io::ErrorKind::NotFound => {}
                Err(remove_error) => {
                    return Err(remove_error)
                        .context("remove newly-created file after verification failure")
                }
            },
        }
        return Err(error).context("file apply rolled back after verification failure");
    }
    Ok(())
}

fn verify_file_rollback(path: &Path, expected: Option<&[u8]>, mode: Option<u32>) -> Result<()> {
    match expected {
        Some(bytes) => {
            let metadata = safe_regular_file_metadata(path)?
                .ok_or_else(|| anyhow!("rolled-back settings file is missing"))?;
            if fs::read(path)? != bytes {
                bail!("rolled-back settings file bytes differ from the original");
            }
            if mode.is_some_and(|expected| metadata.permissions().mode() & 0o7777 != expected) {
                bail!("rolled-back settings file mode differs from the original");
            }
        }
        None if path.exists() => bail!("new settings file still exists after rollback"),
        None => {}
    }
    Ok(())
}
pub fn checksum(bytes: &[u8]) -> String {
    format!("sha256:{:x}", Sha256::digest(bytes))
}

pub fn parse_command_value(output: &str, value_type: ValueType) -> Result<Value> {
    let value = output.trim();
    match value_type {
        ValueType::Bool => match value.to_ascii_lowercase().as_str() {
            "true" | "1" => Ok(Value::Bool(true)),
            "false" | "0" => Ok(Value::Bool(false)),
            _ => bail!("expected bool command output, got a different value"),
        },
        ValueType::Int => Ok(Value::from(
            value.parse::<i64>().context("parse integer output")?,
        )),
        ValueType::Float => {
            let number = serde_json::Number::from_f64(
                value
                    .parse::<f64>()
                    .context("parse floating-point output")?,
            )
            .ok_or_else(|| anyhow!("floating-point output is not finite"))?;
            Ok(Value::Number(number))
        }
        ValueType::String => Ok(Value::String(value.to_owned())),
        _ => bail!("command_value supports only bool, int, float, and string"),
    }
}

pub fn command_value_set_arguments(
    entry: &CommandValueEntry,
    value: &Value,
) -> Result<Vec<String>> {
    if !validate_value_type(value, entry.value_type) {
        bail!(
            "command_value {} must be {}",
            entry.name,
            entry.value_type.as_str()
        );
    }
    let canonical = match value {
        Value::Bool(value) => value.to_string(),
        Value::Number(value) => value.to_string(),
        Value::String(value) => value.clone(),
        _ => unreachable!("validated scalar command value"),
    };
    Ok(entry
        .set
        .arguments
        .iter()
        .map(|argument| argument.replace("{value}", &canonical))
        .collect())
}

pub fn command_value_set_display(entry: &CommandValueEntry, value: &Value) -> Result<String> {
    Ok(render_owned_command(
        &entry.set.executable,
        &command_value_set_arguments(entry, value)?,
    ))
}

fn verify_command_value<R: CommandRunner>(
    runner: &mut R,
    entry: &CommandValueEntry,
    expected: &Value,
) -> Result<()> {
    let output = runner.run_owned(&entry.get.executable, &entry.get.arguments)?;
    let readback = parse_command_value(&output, entry.value_type)?;
    if equal_typed(Some(&readback), expected, entry.value_type) {
        Ok(())
    } else {
        bail!(
            "command_value {} semantic read-back differs from expected value",
            entry.name
        )
    }
}
fn sanitize(value: &str) -> String {
    value
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '-' })
        .collect()
}

#[cfg(test)]
mod security_tests {
    use super::{
        reject_unsafe_bundle_metadata, safe_regular_file_read_path_in_store,
        validate_sandbox_target, write_bytes_atomic,
    };
    use std::fs;
    use std::os::unix::fs::{symlink, PermissionsExt};

    #[test]
    fn bundle_metadata_rejects_symlinks_writable_files_and_hard_links() {
        let directory = tempfile::TempDir::new().unwrap();
        let regular = directory.path().join("Info.plist");
        fs::write(&regular, b"plist").unwrap();
        fs::set_permissions(&regular, fs::Permissions::from_mode(0o644)).unwrap();
        reject_unsafe_bundle_metadata(&regular, false).unwrap();

        let linked = directory.path().join("Linked.plist");
        symlink(&regular, &linked).unwrap();
        assert!(reject_unsafe_bundle_metadata(&linked, false)
            .unwrap_err()
            .to_string()
            .contains("symlink"));

        fs::set_permissions(&regular, fs::Permissions::from_mode(0o666)).unwrap();
        assert!(reject_unsafe_bundle_metadata(&regular, false)
            .unwrap_err()
            .to_string()
            .contains("group/world writable"));
        fs::set_permissions(&regular, fs::Permissions::from_mode(0o644)).unwrap();

        let hard_link = directory.path().join("HardLinked.plist");
        fs::hard_link(&regular, &hard_link).unwrap();
        assert!(reject_unsafe_bundle_metadata(&regular, false)
            .unwrap_err()
            .to_string()
            .contains("unsafe link count"));
    }

    #[test]
    fn settings_writes_reject_symlinks_and_hard_links() {
        let directory = tempfile::TempDir::new().unwrap();
        let regular = directory.path().join("settings.json");
        fs::write(&regular, b"{}\n").unwrap();
        let symlink_path = directory.path().join("linked.json");
        symlink(&regular, &symlink_path).unwrap();
        assert!(
            write_bytes_atomic(&symlink_path, b"{\"safe\":true}\n", "0600")
                .unwrap_err()
                .to_string()
                .contains("symlink")
        );

        let hard_link = directory.path().join("hard.json");
        fs::hard_link(&regular, &hard_link).unwrap();
        assert!(write_bytes_atomic(&regular, b"{\"safe\":true}\n", "0600")
            .unwrap_err()
            .to_string()
            .contains("hard-link"));
        assert_eq!(fs::read(&hard_link).unwrap(), b"{}\n");
    }

    #[test]
    fn settings_reads_allow_only_read_only_store_symlinks() {
        let directory = tempfile::TempDir::new().unwrap();
        let store = directory.path().join("store");
        fs::create_dir(&store).unwrap();
        let store_file = store.join("managed-config");
        fs::write(&store_file, b"managed\n").unwrap();
        fs::set_permissions(&store_file, fs::Permissions::from_mode(0o444)).unwrap();

        let managed_link = directory.path().join("managed-link");
        symlink(&store_file, &managed_link).unwrap();
        assert_eq!(
            safe_regular_file_read_path_in_store(&managed_link, &store).unwrap(),
            fs::canonicalize(&store_file).unwrap()
        );

        let outside_file = directory.path().join("outside-config");
        fs::write(&outside_file, b"outside\n").unwrap();
        let outside_link = directory.path().join("outside-link");
        symlink(&outside_file, &outside_link).unwrap();
        assert!(safe_regular_file_read_path_in_store(&outside_link, &store)
            .unwrap_err()
            .to_string()
            .contains("outside the Nix store"));

        fs::set_permissions(&store_file, fs::Permissions::from_mode(0o666)).unwrap();
        assert!(safe_regular_file_read_path_in_store(&managed_link, &store)
            .unwrap_err()
            .to_string()
            .contains("group/world writable"));
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn settings_writes_preserve_restrictive_mode_and_extended_attributes() {
        use std::process::Command;

        let directory = tempfile::TempDir::new().unwrap();
        let path = directory.path().join("private-settings");
        fs::write(&path, b"secret=old\n").unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o600)).unwrap();
        let status = Command::new("/usr/bin/xattr")
            .args(["-w", "com.nix-me.test", "preserved"])
            .arg(&path)
            .status()
            .unwrap();
        assert!(status.success());

        write_bytes_atomic(&path, b"secret=new\n", "0644").unwrap();

        assert_eq!(
            fs::metadata(&path).unwrap().permissions().mode() & 0o777,
            0o600
        );
        let output = Command::new("/usr/bin/xattr")
            .args(["-p", "com.nix-me.test"])
            .arg(&path)
            .output()
            .unwrap();
        assert!(output.status.success());
        assert_eq!(String::from_utf8_lossy(&output.stdout).trim(), "preserved");
    }

    #[test]
    fn sandbox_confinement_rejects_symlink_components_and_escape_targets() {
        let directory = tempfile::TempDir::new().unwrap();
        let root = directory.path().join("container/Data");
        fs::create_dir_all(&root).unwrap();
        let outside = directory.path().join("outside");
        fs::create_dir_all(&outside).unwrap();
        symlink(&outside, root.join("linked")).unwrap();
        assert!(
            validate_sandbox_target(&root, &root.join("linked/settings.json"))
                .unwrap_err()
                .to_string()
                .contains("symlink")
        );
        assert!(validate_sandbox_target(&root, &outside.join("settings.json")).is_err());
    }
}
