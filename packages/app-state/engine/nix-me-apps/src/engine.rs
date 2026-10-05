use std::collections::BTreeSet;
use std::fs;
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

use anyhow::{anyhow, bail, Context, Result};
use base64::Engine as _;
use serde_json::{Map, Value};
use sha2::{Digest, Sha256};

use crate::model::*;
use crate::plan::*;
use crate::prefs::PrefStore;
use crate::runner::{Clock, CommandRunner};
use crate::state::{AppState, ArtifactState, State};

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
            if !self.detected(recipe)? {
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
                preflight_errors.push(error.to_string());
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

    fn detected(&mut self, recipe: &Recipe) -> Result<bool> {
        let Some(d) = &recipe.detect else {
            return Ok(true);
        };
        if let Some(path) = &d.app_path {
            if Path::new(path).exists() {
                return Ok(true);
            }
        }
        if let Some(command) = &d.command {
            return Ok(self.runner.succeeds(command));
        }
        Ok(d.app_path.is_none())
    }
    fn preflight(&self, recipe: &Recipe) -> Result<()> {
        if recipe.sandboxed {
            let root = home_dir()?
                .join("Library/Containers")
                .join(&recipe.bundle_id)
                .join("Data");
            if root.exists() && !root.read_dir().is_ok() {
                bail!("{} needs Full Disk Access: System Settings > Privacy & Security > Full Disk Access",recipe.name);
            }
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
            } else if requirement == "accessibility" && !mac_permissions::accessibility_granted() {
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
        let current = if path.exists() {
            Some(read_structured(&path, e.format)?)
        } else {
            None
        };
        let desired = if e.merge == Merge::DeepMerge {
            let mut merged = current.clone().unwrap_or_else(|| Value::Object(Map::new()));
            crate::model::deep_merge(&mut merged, model);
            merged
        } else {
            model.clone()
        };
        if current.as_ref() == Some(&desired) {
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
            op: if e.merge == Merge::DeepMerge {
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
        let mut failed = false;
        let mut touched_domains = BTreeSet::new();
        let mut touched_apps = BTreeSet::new();
        let profile = Value::Object(values.clone());
        for app_plan in &mut plan.apps {
            let Some(recipe) = recipes.iter().find(|r| r.id == app_plan.id) else {
                continue;
            };
            let app_values = values.get(&recipe.id).unwrap();
            let models = match self.bind_models(recipe, app_values, values) {
                Ok(v) => v,
                Err(e) => {
                    failed = true;
                    self.warnings.push(e.to_string());
                    continue;
                }
            };
            for (index, entry_plan) in app_plan.entries.iter_mut().enumerate() {
                let entry = &recipe.config[index];
                let out_of_band = entry_plan.drift.iter().any(|d| d.reason == "out_of_band");
                if out_of_band && self.options.force {
                    entry_plan.drift.retain(|d| d.reason != "out_of_band");
                }
                for action in &mut entry_plan.actions {
                    let outcome = if out_of_band && !self.options.force {
                        Err(anyhow!("out-of-band file drift; rerun with --force"))
                    } else {
                        self.execute_action(
                            recipe,
                            entry,
                            action,
                            &models[index],
                            &profile,
                            &mut touched_domains,
                        )
                    };
                    match outcome {
                        Ok(()) => action.result = Some("ok".into()),
                        Err(e) => {
                            if out_of_band && !self.options.force {
                                action.result = Some("skipped".into());
                            } else {
                                action.result = Some("failed".into());
                                failed = true;
                            }
                            action.error = Some(e.to_string());
                        }
                    }
                }
                let all_ok = entry_plan
                    .actions
                    .iter()
                    .all(|a| a.result.as_deref() == Some("ok"))
                    || entry_plan.actions.is_empty();
                if entry_plan
                    .actions
                    .iter()
                    .any(|action| action.result.as_deref() == Some("ok"))
                {
                    touched_apps.insert(recipe.id.clone());
                }
                if all_ok && !entry_plan.actions.is_empty() {
                    let app = self.state.apps.entry(recipe.id.clone()).or_default();
                    let ent = app.entries.entry(entry_plan.bind.clone()).or_default();
                    ent.applied_at = self.clock.now();
                    match entry {
                        ConfigEntry::Defaults(_) => ent.last_applied = models[index].clone(),
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
        for domain in touched_domains {
            if let Err(e) = self.prefs.synchronize(&domain) {
                failed = true;
                self.warnings.push(e.to_string());
            }
        }
        let commands = touched_apps
            .iter()
            .filter_map(|id| recipes.iter().find(|recipe| &recipe.id == id))
            .filter_map(poke_command)
            .collect::<BTreeSet<_>>();
        for command in commands {
            if let Err(error) = self.runner.run(&command) {
                failed = true;
                self.warnings.push(error.to_string());
            }
        }
        plan.mode = "apply".into();
        plan.recompute_summary_and_exit(true, failed);
        plan
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
                domains.insert(e.domain.clone());
                Ok(())
            }
            ConfigEntry::File(e) => {
                let path = PathBuf::from(&action.target);
                write_structured_atomic(&path, e.format, action.desired.as_ref().unwrap(), &e.mode)
            }
            ConfigEntry::Command(e) => {
                self.run_command_with_retries(&command_action_command(e, action)?)
            }
            ConfigEntry::GeneratedImport(e) => {
                if action.op == "deliver" {
                    return self.runner.run(&action.target).map(|_| ());
                }
                if action.op != "materialize" {
                    return Ok(());
                }
                let model = model.as_ref().unwrap();
                let app_state = self
                    .state
                    .apps
                    .entry(recipe.id.clone())
                    .or_insert_with(AppState::default);
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
                fs::write(path, bytes)?;
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
fn resolve_file_path(recipe: &Recipe, path: &str) -> Result<PathBuf> {
    if recipe.sandboxed {
        let relative = path
            .strip_prefix("~/")
            .unwrap_or(path.trim_start_matches('/'));
        Ok(home_dir()?
            .join("Library/Containers")
            .join(&recipe.bundle_id)
            .join("Data")
            .join(relative))
    } else {
        expand_home(path)
    }
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
    }
}
fn read_structured(path: &Path, format: FileFormat) -> Result<Value> {
    let bytes = fs::read(path)?;
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
    })
}
fn write_structured_atomic(
    path: &Path,
    format: FileFormat,
    value: &Value,
    mode: &str,
) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let parent = path.parent().unwrap_or(Path::new("."));
    let mut temp = tempfile::NamedTempFile::new_in(parent)?;
    temp.write_all(&structured_bytes(format, value)?)?;
    temp.as_file().sync_all()?;
    let permissions = u32::from_str_radix(mode.trim_start_matches('0'), 8)?;
    temp.as_file()
        .set_permissions(fs::Permissions::from_mode(permissions))?;
    temp.persist(path).map_err(|e| e.error)?;
    Ok(())
}
pub fn checksum(bytes: &[u8]) -> String {
    format!("sha256:{:x}", Sha256::digest(bytes))
}
fn sanitize(value: &str) -> String {
    value
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '-' })
        .collect()
}
