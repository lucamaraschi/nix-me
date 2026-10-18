use std::collections::{BTreeSet, VecDeque};
use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{anyhow, Result};
use nix_me_apps::engine::{Engine, Options};
use nix_me_apps::model::{load_recipe, load_values};
use nix_me_apps::prefs::FakePrefStore;
use nix_me_apps::runner::{CommandRunner, FixedClock, ReplayCommandRunner};
use nix_me_apps::snapshot::current_values;
use nix_me_apps::state::State;
use serde_json::{json, Value};
use tempfile::TempDir;

const NOW: &str = "2026-10-15T18:00:00Z";

fn write(path: &Path, contents: &str) {
    fs::write(path, contents).unwrap();
}

fn recipe(dir: &TempDir, body: &str) -> nix_me_apps::model::Recipe {
    let path = dir.path().join("test-app.yaml");
    write(
        &path,
        &format!(
            "schema_version: 1\nid: test-app\nname: Test App\nbundle_id: com.example.TestApp\n{body}\nverified: null\n"
        ),
    );
    load_recipe(&path).unwrap()
}

fn value_map(dir: &TempDir, contents: &str) -> serde_json::Map<String, Value> {
    let path = dir.path().join("values.yaml");
    write(&path, contents);
    load_values(&[path]).unwrap()
}

#[test]
fn json_pointer_capture_and_apply_never_export_unowned_electron_state() {
    let dir = TempDir::new().unwrap();
    let target = dir.path().join("Preferences");
    write(
        &target,
        include_str!("../../fixtures/adapters/electron-preferences.json"),
    );
    let recipe = recipe(
        &dir,
        &format!(
            "config:\n  - kind: file\n    binds: settings\n    path: {:?}\n    format: json\n    merge: deep_merge\n    paths:\n      allow:\n        - /appearance/theme\n        - /updates/channel\n      sensitive:\n        - /auth/token",
            target.display().to_string()
        ),
    );

    let prefs = FakePrefStore::default();
    let mut capture_runner = ReplayCommandRunner::default();
    let snapshot = current_values(
        std::slice::from_ref(&recipe),
        &BTreeSet::new(),
        &prefs,
        &mut capture_runner,
    );
    assert_eq!(
        snapshot["values"]["test-app"]["settings"],
        json!({"appearance":{"theme":"dark"},"updates":{"channel":"stable"}})
    );
    assert!(snapshot["values"]["test-app"]["settings"]["auth"].is_null());
    assert!(snapshot["values"]["test-app"]["settings"]["workspace"].is_null());

    let mut values = snapshot["values"].as_object().unwrap().clone();
    values["test-app"]["settings"]["appearance"]["theme"] = json!("light");
    let mut prefs = FakePrefStore::default();
    let mut runner = ReplayCommandRunner::default();
    let clock = FixedClock(NOW.into());
    let mut state = State::default();
    let mut engine = Engine {
        prefs: &mut prefs,
        runner: &mut runner,
        clock: &clock,
        state: &mut state,
        state_dir: dir.path().into(),
        options: Options {
            force: true,
            ..Options::default()
        },
        warnings: vec![],
    };
    let plan = engine
        .plan(std::slice::from_ref(&recipe), &values, "diff")
        .unwrap();
    assert!(plan.has_actions());
    let applied = engine.apply(std::slice::from_ref(&recipe), &values, plan);
    assert_eq!(applied.exit_code, 0);

    let result: Value = serde_json::from_slice(&fs::read(&target).unwrap()).unwrap();
    assert_eq!(result["appearance"]["theme"], "light");
    assert_eq!(result["appearance"]["zoom"], 1);
    assert_eq!(
        result["auth"]["token"],
        "fixture-secret-must-not-be-exported"
    );
    assert_eq!(result["workspace"]["recent"], json!(["private-project"]));
    assert_eq!(
        engine.plan(&[recipe], &values, "diff").unwrap().exit_code,
        0
    );
}

#[test]
fn ini_engine_round_trip_preserves_comments_unknown_sections_and_secrets() {
    let dir = TempDir::new().unwrap();
    let target = dir.path().join("global.ini");
    write(
        &target,
        include_str!("../../fixtures/adapters/obs-global.ini"),
    );
    let recipe = recipe(
        &dir,
        &format!(
            "config:\n  - kind: file\n    binds: settings\n    path: {:?}\n    format: ini\n    paths:\n      allow:\n        - /global/Language\n        - /sections/General/Theme\n      sensitive:\n        - /sections/PluginState/private-token",
            target.display().to_string()
        ),
    );
    let values = value_map(
        &dir,
        "test-app:\n  settings:\n    global: {Language: en-GB}\n    sections:\n      General: {Theme: Light}\n",
    );

    let mut prefs = FakePrefStore::default();
    let mut runner = ReplayCommandRunner::default();
    let clock = FixedClock(NOW.into());
    let mut state = State::default();
    let mut engine = Engine {
        prefs: &mut prefs,
        runner: &mut runner,
        clock: &clock,
        state: &mut state,
        state_dir: dir.path().into(),
        options: Options {
            force: true,
            ..Options::default()
        },
        warnings: vec![],
    };
    let plan = engine
        .plan(std::slice::from_ref(&recipe), &values, "diff")
        .unwrap();
    let applied = engine.apply(std::slice::from_ref(&recipe), &values, plan);
    assert_eq!(applied.exit_code, 0);
    let result = fs::read_to_string(&target).unwrap();
    assert!(result.starts_with("; OBS fixture with comments"));
    assert!(result.contains("Language=en-GB"));
    assert!(result.contains("Theme = Light"));
    assert!(result.contains("OpenStatsOnStartup=false"));
    assert!(result.contains("private-token=fixture-secret-must-not-be-exported"));
    assert_eq!(
        engine.plan(&[recipe], &values, "diff").unwrap().exit_code,
        0
    );
}

#[test]
fn unsupported_application_major_is_refused_before_planning() {
    let dir = TempDir::new().unwrap();
    let recipe = recipe(
        &dir,
        "app_version:\n  command: app --version\n  supported_majors: [4]\nconfig:\n  - kind: manual\n    step: No mutation",
    );
    let values = value_map(&dir, "test-app: {}\n");
    let mut prefs = FakePrefStore::default();
    let mut runner = ReplayCommandRunner::default();
    runner
        .outputs
        .insert("app --version".into(), Ok("App 5.0.0".into()));
    let clock = FixedClock(NOW.into());
    let mut state = State::default();
    let mut engine = Engine {
        prefs: &mut prefs,
        runner: &mut runner,
        clock: &clock,
        state: &mut state,
        state_dir: dir.path().into(),
        options: Options::default(),
        warnings: vec![],
    };
    let error = engine.plan(&[recipe], &values, "diff").unwrap_err();
    assert!(error
        .to_string()
        .contains("unsupported application major version 5"));
    assert_eq!(engine.runner.recorded, ["app --version"]);
}

#[derive(Default)]
struct FileCheckRunner {
    reject_candidate: bool,
    reject_verify: bool,
    recorded: Vec<String>,
}

impl CommandRunner for FileCheckRunner {
    fn run(&mut self, command: &str) -> Result<String> {
        self.recorded.push(command.to_owned());
        let arguments = shell_words::split(command)?;
        match arguments.first().map(String::as_str) {
            Some("check-candidate") => {
                let candidate = arguments
                    .get(1)
                    .ok_or_else(|| anyhow!("candidate path missing"))?;
                let contents = fs::read_to_string(candidate)?;
                if self.reject_candidate || contents.contains("invalid") {
                    Err(anyhow!("candidate rejected"))
                } else {
                    Ok(String::new())
                }
            }
            Some("verify-live") if self.reject_verify => Err(anyhow!("verification rejected")),
            Some("verify-live") => Ok(String::new()),
            _ => Err(anyhow!("unexpected command {command}")),
        }
    }

    fn run_owned(&mut self, program: &str, arguments: &[String]) -> Result<String> {
        self.run(&nix_me_apps::runner::render_owned_command(
            program, arguments,
        ))
    }
}

fn apply_reviewed_source(
    dir: &TempDir,
    desired: &str,
    runner: &mut FileCheckRunner,
) -> (nix_me_apps::plan::Plan, PathBuf) {
    let target = dir.path().join("init.lua");
    write(&target, "valid-old\n");
    let recipe = recipe(
        dir,
        &format!(
            "config:\n  - kind: file\n    binds: source\n    path: {:?}\n    format: text\n    export: reviewed_text\n    checks:\n      preflight: check-candidate {{file}}\n      verify: verify-live {{path}}",
            target.display().to_string()
        ),
    );
    let values = value_map(dir, &format!("test-app:\n  source: {:?}\n", desired));
    let mut prefs = FakePrefStore::default();
    let clock = FixedClock(NOW.into());
    let mut state = State::default();
    let mut engine = Engine {
        prefs: &mut prefs,
        runner,
        clock: &clock,
        state: &mut state,
        state_dir: dir.path().into(),
        options: Options {
            force: true,
            ..Options::default()
        },
        warnings: vec![],
    };
    let plan = engine
        .plan(std::slice::from_ref(&recipe), &values, "diff")
        .unwrap();
    (engine.apply(&[recipe], &values, plan), target)
}

#[test]
fn reviewed_source_preflight_does_not_mutate_and_verify_failure_rolls_back() {
    let candidate_dir = TempDir::new().unwrap();
    let mut candidate_runner = FileCheckRunner {
        reject_candidate: true,
        ..FileCheckRunner::default()
    };
    let (candidate_plan, candidate_target) =
        apply_reviewed_source(&candidate_dir, "valid-new\n", &mut candidate_runner);
    assert_eq!(candidate_plan.exit_code, 5);
    assert_eq!(fs::read_to_string(candidate_target).unwrap(), "valid-old\n");

    let verify_dir = TempDir::new().unwrap();
    let mut verify_runner = FileCheckRunner {
        reject_verify: true,
        ..FileCheckRunner::default()
    };
    let (verify_plan, verify_target) =
        apply_reviewed_source(&verify_dir, "valid-new\n", &mut verify_runner);
    assert_eq!(verify_plan.exit_code, 5);
    assert_eq!(fs::read_to_string(verify_target).unwrap(), "valid-old\n");
}

struct ScalarRunner {
    value: bool,
    ignore_writes: bool,
    reads: VecDeque<bool>,
    recorded: Vec<String>,
}

impl CommandRunner for ScalarRunner {
    fn run(&mut self, command: &str) -> Result<String> {
        self.recorded.push(command.to_owned());
        match command {
            "tool get" => Ok(self.reads.pop_front().unwrap_or(self.value).to_string()),
            "tool set true" => {
                if !self.ignore_writes {
                    self.value = true;
                }
                Ok(String::new())
            }
            "tool set false" => {
                if !self.ignore_writes {
                    self.value = false;
                }
                Ok(String::new())
            }
            _ => Err(anyhow!("unexpected command {command}")),
        }
    }

    fn run_owned(&mut self, program: &str, arguments: &[String]) -> Result<String> {
        let rendered = nix_me_apps::runner::render_owned_command(program, arguments);
        self.recorded.push(rendered);
        match (program, arguments) {
            ("/usr/bin/tool", arguments) if arguments == ["get"] => {
                Ok(self.reads.pop_front().unwrap_or(self.value).to_string())
            }
            ("/usr/bin/tool", arguments) if arguments == ["set", "true"] => {
                if !self.ignore_writes {
                    self.value = true;
                }
                Ok(String::new())
            }
            ("/usr/bin/tool", arguments) if arguments == ["set", "false"] => {
                if !self.ignore_writes {
                    self.value = false;
                }
                Ok(String::new())
            }
            _ => Err(anyhow!("unexpected owned command")),
        }
    }
}

#[test]
fn typed_scalar_command_requires_semantic_readback() {
    let dir = TempDir::new().unwrap();
    let recipe = recipe(
        &dir,
        "config:\n  - kind: command_value\n    name: accept_routes\n    type: bool\n    get: {executable: /usr/bin/tool, arguments: [get]}\n    set: {executable: /usr/bin/tool, arguments: [set, '{value}']}",
    );
    let values = value_map(&dir, "test-app: {accept_routes: true}\n");
    let mut prefs = FakePrefStore::default();
    let clock = FixedClock(NOW.into());
    let mut state = State::default();
    let mut runner = ScalarRunner {
        value: false,
        ignore_writes: false,
        reads: VecDeque::new(),
        recorded: vec![],
    };
    let mut engine = Engine {
        prefs: &mut prefs,
        runner: &mut runner,
        clock: &clock,
        state: &mut state,
        state_dir: dir.path().into(),
        options: Options::default(),
        warnings: vec![],
    };
    let plan = engine
        .plan(std::slice::from_ref(&recipe), &values, "diff")
        .unwrap();
    let applied = engine.apply(std::slice::from_ref(&recipe), &values, plan);
    assert_eq!(applied.exit_code, 0);
    assert!(engine.runner.value);
    assert_eq!(
        engine.plan(&[recipe], &values, "diff").unwrap().exit_code,
        0
    );
}

#[test]
fn typed_scalar_command_failure_is_reported_and_previous_value_is_restored() {
    let dir = TempDir::new().unwrap();
    let recipe = recipe(
        &dir,
        "config:\n  - kind: command_value\n    name: accept_routes\n    type: bool\n    get: {executable: /usr/bin/tool, arguments: [get]}\n    set: {executable: /usr/bin/tool, arguments: [set, '{value}']}",
    );
    let values = value_map(&dir, "test-app: {accept_routes: true}\n");
    let mut prefs = FakePrefStore::default();
    let clock = FixedClock(NOW.into());
    let mut state = State::default();
    let mut runner = ScalarRunner {
        value: false,
        ignore_writes: true,
        reads: VecDeque::new(),
        recorded: vec![],
    };
    let mut engine = Engine {
        prefs: &mut prefs,
        runner: &mut runner,
        clock: &clock,
        state: &mut state,
        state_dir: dir.path().into(),
        options: Options::default(),
        warnings: vec![],
    };
    let plan = engine
        .plan(std::slice::from_ref(&recipe), &values, "diff")
        .unwrap();
    let applied = engine.apply(&[recipe], &values, plan);
    assert_eq!(applied.exit_code, 5);
    assert!(!engine.runner.value);
    assert!(engine
        .runner
        .recorded
        .iter()
        .any(|command| command == "/usr/bin/tool set false"));
    assert!(engine
        .warnings
        .iter()
        .any(|warning| warning.contains("rolled back and verified")));
}

#[derive(Default)]
struct ArgumentRunner {
    value: String,
    calls: Vec<(String, Vec<String>)>,
}

impl CommandRunner for ArgumentRunner {
    fn run(&mut self, command: &str) -> Result<String> {
        Err(anyhow!(
            "shell execution is forbidden for command_value: {command}"
        ))
    }

    fn run_owned(&mut self, program: &str, arguments: &[String]) -> Result<String> {
        self.calls.push((program.to_owned(), arguments.to_vec()));
        match arguments {
            [operation] if operation == "get" => Ok(self.value.clone()),
            [operation, value] if operation == "set" => {
                self.value = value.clone();
                Ok(String::new())
            }
            _ => Err(anyhow!("unexpected structured invocation")),
        }
    }
}

#[test]
fn typed_scalar_values_are_process_arguments_never_shell_source() {
    let dir = TempDir::new().unwrap();
    let marker = dir.path().join("must-not-exist");
    let malicious = format!("$(touch {})", marker.display());
    let recipe = recipe(
        &dir,
        "config:\n  - kind: command_value\n    name: label\n    type: string\n    get: {executable: /usr/bin/tool, arguments: [get]}\n    set: {executable: /usr/bin/tool, arguments: [set, '{value}']}",
    );
    let values = value_map(&dir, &format!("test-app:\n  label: {:?}\n", malicious));
    let mut prefs = FakePrefStore::default();
    let mut runner = ArgumentRunner {
        value: "old".into(),
        ..ArgumentRunner::default()
    };
    let clock = FixedClock(NOW.into());
    let mut state = State::default();
    let mut engine = Engine {
        prefs: &mut prefs,
        runner: &mut runner,
        clock: &clock,
        state: &mut state,
        state_dir: dir.path().into(),
        options: Options::default(),
        warnings: vec![],
    };
    let plan = engine
        .plan(std::slice::from_ref(&recipe), &values, "diff")
        .unwrap();
    let applied = engine.apply(&[recipe], &values, plan);
    assert_eq!(applied.exit_code, 0);
    assert_eq!(engine.runner.value, malicious);
    assert!(!marker.exists());
    assert!(engine
        .runner
        .calls
        .iter()
        .any(|(_, arguments)| arguments == &["set".to_owned(), malicious.clone()]));
}

#[test]
fn later_failure_stops_apply_and_rolls_back_every_prior_file() {
    let dir = TempDir::new().unwrap();
    let first = dir.path().join("first.conf");
    let second = dir.path().join("second.conf");
    let third = dir.path().join("third.conf");
    write(&first, "old-first\n");
    write(&second, "old-second\n");
    write(&third, "old-third\n");
    let recipe = recipe(
        &dir,
        &format!(
            "config:\n  - kind: file\n    binds: first\n    path: {:?}\n    format: text\n    checks: {{preflight: 'check-candidate {{file}}'}}\n  - kind: file\n    binds: second\n    path: {:?}\n    format: text\n    checks: {{preflight: 'check-candidate {{file}}'}}\n  - kind: file\n    binds: third\n    path: {:?}\n    format: text",
            first.display().to_string(),
            second.display().to_string(),
            third.display().to_string()
        ),
    );
    let values = value_map(
        &dir,
        "test-app:\n  first: 'new-first\n'\n  second: 'invalid\n'\n  third: 'new-third\n'\n",
    );
    let mut prefs = FakePrefStore::default();
    let mut runner = FileCheckRunner::default();
    let clock = FixedClock(NOW.into());
    let mut state = State::default();
    let mut engine = Engine {
        prefs: &mut prefs,
        runner: &mut runner,
        clock: &clock,
        state: &mut state,
        state_dir: dir.path().into(),
        options: Options {
            force: true,
            ..Options::default()
        },
        warnings: vec![],
    };
    let plan = engine
        .plan(std::slice::from_ref(&recipe), &values, "diff")
        .unwrap();
    let applied = engine.apply(&[recipe], &values, plan);
    assert_eq!(applied.exit_code, 5);
    assert_eq!(fs::read_to_string(first).unwrap(), "old-first\n");
    assert_eq!(fs::read_to_string(second).unwrap(), "old-second\n");
    assert_eq!(fs::read_to_string(third).unwrap(), "old-third\n");
    assert!(engine.state.apps.is_empty());
    assert_eq!(
        applied.apps[0].entries[0].actions[0].result.as_deref(),
        Some("rolled_back")
    );
    assert_eq!(
        applied.apps[0].entries[2].actions[0].result.as_deref(),
        Some("skipped")
    );
}

#[test]
fn poke_failure_rolls_back_and_verifies_prior_mutations() {
    let dir = TempDir::new().unwrap();
    let target = dir.path().join("settings.json");
    write(&target, "{\"enabled\":false}\n");
    let recipe = recipe(
        &dir,
        &format!(
            "config:\n  - kind: file\n    binds: settings\n    path: {:?}\n    format: json\napply:\n  poke: script\n  poke_script: reload",
            target.display().to_string()
        ),
    );
    let values = value_map(&dir, "test-app:\n  settings: {enabled: true}\n");
    let mut prefs = FakePrefStore::default();
    let mut runner = RetryPokeRunner::default();
    let clock = FixedClock(NOW.into());
    let mut state = State::default();
    let mut engine = Engine {
        prefs: &mut prefs,
        runner: &mut runner,
        clock: &clock,
        state: &mut state,
        state_dir: dir.path().into(),
        options: Options {
            force: true,
            ..Options::default()
        },
        warnings: vec![],
    };
    let plan = engine
        .plan(std::slice::from_ref(&recipe), &values, "diff")
        .unwrap();
    let applied = engine.apply(&[recipe], &values, plan);
    assert_eq!(applied.exit_code, 5);
    assert_eq!(fs::read_to_string(target).unwrap(), "{\"enabled\":false}\n");
    assert_eq!(engine.runner.reloads, 2);
    assert!(engine
        .warnings
        .iter()
        .any(|warning| warning.contains("all completed mutations were rolled back and verified")));
}

#[derive(Default)]
struct RetryPokeRunner {
    reloads: usize,
}

impl CommandRunner for RetryPokeRunner {
    fn run(&mut self, command: &str) -> Result<String> {
        if command != "reload" {
            return Err(anyhow!("unexpected command {command}"));
        }
        self.reloads += 1;
        if self.reloads == 1 {
            Err(anyhow!("injected initial reload failure"))
        } else {
            Ok(String::new())
        }
    }

    fn run_owned(&mut self, program: &str, arguments: &[String]) -> Result<String> {
        self.run(&nix_me_apps::runner::render_owned_command(
            program, arguments,
        ))
    }
}

struct RollbackFailRunner {
    value: bool,
    reads: usize,
}

impl CommandRunner for RollbackFailRunner {
    fn run(&mut self, command: &str) -> Result<String> {
        Err(anyhow!("unexpected shell command {command}"))
    }

    fn run_owned(&mut self, _program: &str, arguments: &[String]) -> Result<String> {
        match arguments {
            [operation] if operation == "get" => {
                self.reads += 1;
                if self.reads == 3 {
                    Ok("false".into())
                } else {
                    Ok(self.value.to_string())
                }
            }
            [operation, value] if operation == "set" && value == "true" => {
                self.value = true;
                Ok(String::new())
            }
            [operation, value] if operation == "set" && value == "false" => {
                Err(anyhow!("rollback setter failed"))
            }
            _ => Err(anyhow!("unexpected structured command")),
        }
    }
}

#[test]
fn rollback_failure_is_reported_as_unverified_and_never_as_safe() {
    let dir = TempDir::new().unwrap();
    let recipe = recipe(
        &dir,
        "config:\n  - kind: command_value\n    name: enabled\n    type: bool\n    get: {executable: /usr/bin/tool, arguments: [get]}\n    set: {executable: /usr/bin/tool, arguments: [set, '{value}']}",
    );
    let values = value_map(&dir, "test-app: {enabled: true}\n");
    let mut prefs = FakePrefStore::default();
    let mut runner = RollbackFailRunner {
        value: false,
        reads: 0,
    };
    let clock = FixedClock(NOW.into());
    let mut state = State::default();
    let mut engine = Engine {
        prefs: &mut prefs,
        runner: &mut runner,
        clock: &clock,
        state: &mut state,
        state_dir: dir.path().into(),
        options: Options::default(),
        warnings: vec![],
    };
    let plan = engine
        .plan(std::slice::from_ref(&recipe), &values, "diff")
        .unwrap();
    let applied = engine.apply(&[recipe], &values, plan);
    assert_eq!(applied.exit_code, 5);
    assert!(engine.runner.value);
    assert!(engine
        .warnings
        .iter()
        .any(|warning| warning.contains("rollback could not be proven")));
    assert!(!engine
        .warnings
        .iter()
        .any(|warning| warning.contains("rolled back and verified")));
}

#[test]
fn sandbox_paths_numeric_pointers_and_merge_plans_are_fail_closed() {
    let dir = TempDir::new().unwrap();
    let recipe_path = dir.path().join("invalid.yaml");
    write(
        &recipe_path,
        "schema_version: 1\nid: invalid\nname: Invalid\nbundle_id: com.example.Invalid\nsandboxed: true\nconfig:\n  - kind: file\n    path: ../escape.json\n    format: json\n",
    );
    assert!(load_recipe(&recipe_path)
        .unwrap_err()
        .to_string()
        .contains("relative, normalized container paths"));

    write(
        &recipe_path,
        "schema_version: 1\nid: invalid\nname: Invalid\nbundle_id: com.example.Invalid\nconfig:\n  - kind: file\n    path: /tmp/settings.json\n    format: json\n    paths:\n      allow: [/items/0]\n",
    );
    assert!(load_recipe(&recipe_path).is_err());
    write(
        &recipe_path,
        "schema_version: 1\nid: invalid\nname: Invalid\nbundle_id: com.example.Invalid\nconfig:\n  - kind: file\n    path: /tmp/settings.json\n    format: json\n    paths:\n      allow: [/items/00]\n",
    );
    assert!(load_recipe(&recipe_path).is_err());

    let target = dir.path().join("settings.json");
    write(&target, "{\"theme\":\"dark\",\"private\":true}\n");
    let recipe = recipe(
        &dir,
        &format!(
            "config:\n  - kind: file\n    binds: settings\n    path: {:?}\n    format: json\n    paths:\n      allow: [/theme]",
            target.display().to_string()
        ),
    );
    let values = value_map(&dir, "test-app:\n  settings: {theme: light}\n");
    let mut prefs = FakePrefStore::default();
    let mut runner = ReplayCommandRunner::default();
    let clock = FixedClock(NOW.into());
    let mut state = State::default();
    let mut engine = Engine {
        prefs: &mut prefs,
        runner: &mut runner,
        clock: &clock,
        state: &mut state,
        state_dir: dir.path().into(),
        options: Options {
            force: true,
            ..Options::default()
        },
        warnings: vec![],
    };
    let plan = engine
        .plan(std::slice::from_ref(&recipe), &values, "diff")
        .unwrap();
    assert_eq!(plan.apps[0].entries[0].actions[0].op, "merge_file");
    let applied = engine.apply(&[recipe], &values, plan);
    assert_eq!(applied.exit_code, 0);
    assert_eq!(
        serde_json::from_slice::<Value>(&fs::read(target).unwrap()).unwrap(),
        json!({"theme":"light","private":true})
    );
}

#[test]
fn path_policy_schema_refuses_missing_allowlists_and_redaction_overlap() {
    let dir = TempDir::new().unwrap();
    let path = dir.path().join("test-app.yaml");
    write(
        &path,
        "schema_version: 1\nid: test-app\nname: Test\nbundle_id: com.example.Test\nconfig:\n  - kind: file\n    path: /tmp/settings.ini\n    format: ini\n",
    );
    assert!(load_recipe(&path)
        .unwrap_err()
        .to_string()
        .contains("require an explicit path allowlist"));

    write(
        &path,
        "schema_version: 1\nid: test-app\nname: Test\nbundle_id: com.example.Test\nconfig:\n  - kind: file\n    path: /tmp/settings.conf\n    format: key_value\n    paths:\n      allow: [/theme]\n",
    );
    assert!(load_recipe(&path)
        .unwrap_err()
        .to_string()
        .contains("key_value paths must start with /values/"));

    write(
        &path,
        "schema_version: 1\nid: test-app\nname: Test\nbundle_id: com.example.Test\nconfig:\n  - kind: file\n    path: /tmp/settings.json\n    format: json\n    paths:\n      allow: [/account]\n      sensitive: [/account/token]\n",
    );
    assert!(load_recipe(&path)
        .unwrap_err()
        .to_string()
        .contains("unsafe path policy"));
}

#[test]
fn structured_capture_without_an_allowlist_is_default_closed() {
    let dir = TempDir::new().unwrap();
    let target = dir.path().join("settings.json");
    write(&target, r#"{"theme":"dark","token":"secret"}"#);
    let recipe = recipe(
        &dir,
        &format!(
            "config:\n  - kind: file\n    binds: settings\n    path: {:?}\n    format: json",
            target.display().to_string()
        ),
    );
    let prefs = FakePrefStore::default();
    let mut runner = ReplayCommandRunner::default();
    let snapshot = current_values(&[recipe], &BTreeSet::new(), &prefs, &mut runner);
    assert_eq!(snapshot["values"]["test-app"], json!({}));
    assert_eq!(
        snapshot["applications"][0]["skipped"][0]["reason"],
        "structured file export requires an explicit path allowlist"
    );
}
