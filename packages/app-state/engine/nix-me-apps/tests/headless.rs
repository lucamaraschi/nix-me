use std::collections::BTreeSet;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;

use anyhow::{anyhow, Result};
use nix_me_apps::engine::{checksum, poke_command, Engine, Options};
use nix_me_apps::model::{load_recipe, load_values, Artifact, ConfigEntry, FileExport, Host};
use nix_me_apps::prefs::FakePrefStore;
use nix_me_apps::runner::{CommandRunner, FixedClock, ReplayCommandRunner};
use nix_me_apps::snapshot::{current_values_with_options, SnapshotOptions};
use nix_me_apps::state::{ArtifactState, EntryState, State, StateGuard};
use serde_json::Value;
use tempfile::TempDir;

const NOW: &str = "2026-09-06T18:00:00Z";

fn write(path: &Path, text: &str) {
    fs::write(path, text).unwrap();
}
fn recipe_header(config: &str) -> String {
    format!(
        r#"schema_version: 1
id: test-app
name: Test App
bundle_id: com.nix-me.test
config:
{config}
apply:
  poke: none
verified: null
"#
    )
}
fn values(dir: &TempDir, text: &str) -> (std::path::PathBuf, serde_json::Map<String, Value>) {
    let path = dir.path().join("values.yaml");
    write(&path, text);
    let loaded = load_values(std::slice::from_ref(&path)).unwrap();
    (path, loaded)
}
fn loaded_recipe(dir: &TempDir, config: &str) -> nix_me_apps::model::Recipe {
    let path = dir.path().join("test-app.yaml");
    write(&path, &recipe_header(config));
    load_recipe(&path).unwrap()
}

#[test]
fn defaults_diff_apply_diff_is_idempotent_and_typed() {
    let dir = TempDir::new().unwrap();
    let recipe = loaded_recipe(
        &dir,
        r#"  - kind: defaults
    domain: com.nix-me.test
    keys:
      enabled: {type: bool}
      count: {type: int}
      ratio: {type: float}
      title: {type: string}
      items: {type: array}
      options: {type: dict}
      payload: {type: data}
      updated: {type: date}
    unknown_keys: reject"#,
    );
    let (_, values) = values(
        &dir,
        "test-app:\n  enabled: true\n  count: 2\n  ratio: 0.95\n  title: hello\n  items: [one, two]\n  options: {nested: true}\n  payload: AQID\n  updated: 2026-09-06T18:00:00Z\n",
    );
    let mut prefs = FakePrefStore::default();
    prefs.set("com.nix-me.test", "enabled", Host::Any, Value::Bool(false));
    prefs.set(
        "com.nix-me.test",
        "ratio",
        Host::Any,
        serde_json::json!(0.949999988079071),
    );
    let mut runner = ReplayCommandRunner::default();
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
    let first = engine
        .plan(std::slice::from_ref(&recipe), &values, "diff")
        .unwrap();
    assert_eq!(first.exit_code, 2);
    assert_eq!(first.summary.writes, 7);
    assert!(
        first.apps[0].entries[0]
            .actions
            .iter()
            .all(|a| !a.target.ends_with("ratio")),
        "equivalent CF float must not flap"
    );
    let applied = engine.apply(std::slice::from_ref(&recipe), &values, first);
    assert_eq!(applied.exit_code, 0);
    assert!(applied.apps[0].entries[0]
        .actions
        .iter()
        .all(|a| a.result.as_deref() == Some("ok")));
    assert_eq!(engine.prefs.synchronized, vec!["com.nix-me.test"]);
    let second = engine.plan(&[recipe], &values, "diff").unwrap();
    assert_eq!(second.exit_code, 0);
    assert_eq!(second.summary.writes, 0);
}

#[test]
fn forced_key_is_managed_drift_and_never_written() {
    let dir = TempDir::new().unwrap();
    let recipe = loaded_recipe(
        &dir,
        "  - kind: defaults\n    domain: com.nix-me.test\n    keys:\n      enabled: {type: bool}\n",
    );
    let (_, values) = values(&dir, "test-app: {enabled: true}\n");
    let mut prefs = FakePrefStore::default();
    prefs.set("com.nix-me.test", "enabled", Host::Any, Value::Bool(false));
    prefs
        .forced
        .insert(("com.nix-me.test".into(), "enabled".into()), true);
    let mut runner = ReplayCommandRunner::default();
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
    let plan = engine.plan(&[recipe], &values, "diff").unwrap();
    assert_eq!(plan.exit_code, 2);
    assert!(plan.apps[0].entries[0].actions.is_empty());
    assert_eq!(plan.apps[0].entries[0].drift[0].reason, "managed");
}

#[test]
fn semantic_validation_rejects_duplicate_binds_and_text_merge() {
    let dir = TempDir::new().unwrap();
    let path = dir.path().join("bad.yaml");
    write(
        &path,
        &recipe_header(
            "  - kind: defaults\n    domain: one\n  - kind: defaults\n    domain: two\n",
        ),
    );
    assert!(load_recipe(&path)
        .unwrap_err()
        .to_string()
        .contains("duplicate effective bind"));
    write(
        &path,
        &recipe_header(
            "  - kind: file\n    path: /tmp/test\n    format: text\n    merge: deep_merge\n",
        ),
    );
    assert!(load_recipe(&path)
        .unwrap_err()
        .to_string()
        .contains("deep_merge is invalid"));
    write(
        &path,
        &recipe_header(
            "  - kind: file\n    path: /tmp/test\n    format: json\n    export: reviewed_text\n",
        ),
    );
    assert!(load_recipe(&path)
        .unwrap_err()
        .to_string()
        .contains("reviewed_text export is only valid for text files"));
    write(
        &path,
        &recipe_header(
            "  - kind: defaults\n    binds: import\n    domain: one\n  - kind: generated_import\n    source: profile.test-app.import\n    deliver: open {artifact}\n    artifact:\n      pipeline:\n        - json: {}\n",
        ),
    );
    assert!(load_recipe(&path)
        .unwrap_err()
        .to_string()
        .contains("overlapping profile ownership"));
}

#[test]
fn text_export_is_default_closed_and_backward_compatible() {
    let dir = TempDir::new().unwrap();
    let recipe = loaded_recipe(
        &dir,
        "  - kind: file\n    path: /tmp/test\n    format: text\n",
    );
    let ConfigEntry::File(file) = &recipe.config[0] else {
        panic!("expected file entry");
    };
    assert_eq!(file.export, FileExport::None);
}

#[test]
fn reviewed_text_snapshot_apply_round_trip_preserves_exact_bytes() {
    let dir = TempDir::new().unwrap();
    let target = dir.path().join("settings.conf");
    let exact = "font = Mono 13\n\n# comments and spacing stay exact\n";
    write(&target, exact);
    let recipe = loaded_recipe(
        &dir,
        &format!(
            "  - kind: file\n    binds: settings\n    path: {:?}\n    format: text\n    export: reviewed_text\n",
            target.display().to_string()
        ),
    );
    let prefs = FakePrefStore::default();
    let mut capture_runner = ReplayCommandRunner::default();
    let snapshot = current_values_with_options(
        std::slice::from_ref(&recipe),
        &BTreeSet::new(),
        &prefs,
        &mut capture_runner,
        SnapshotOptions {
            confirm_reviewed_text: true,
        },
    );
    let captured_values = snapshot["values"].as_object().unwrap().clone();

    write(&target, "changed\n");
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
        .plan(std::slice::from_ref(&recipe), &captured_values, "diff")
        .unwrap();
    assert_eq!(
        plan.apps[0].entries[0].actions[0].value_type.as_deref(),
        Some("text")
    );
    let applied = engine.apply(std::slice::from_ref(&recipe), &captured_values, plan);
    assert_eq!(applied.exit_code, 0);
    assert_eq!(fs::read(&target).unwrap(), exact.as_bytes());
    assert_eq!(
        engine
            .plan(&[recipe], &captured_values, "diff")
            .unwrap()
            .exit_code,
        0
    );
}

#[test]
fn binding_errors_name_valid_routes_and_explicit_defaults_wins() {
    let dir = TempDir::new().unwrap();
    let recipe = loaded_recipe(
        &dir,
        "  - kind: command\n    name: extensions\n    list: {get: 'list', add: 'add {item}'}\n",
    );
    let (_, bad) = values(&dir, "test-app: {loose: true}\n");
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
        options: Options::default(),
        warnings: vec![],
    };
    let error = engine
        .plan(&[recipe], &bad, "diff")
        .unwrap_err()
        .to_string();
    assert!(error.contains("valid bind names [extensions]"));
    let recipe = loaded_recipe(
        &dir,
        "  - kind: defaults\n    domain: com.nix-me.test\n    keys: {count: {type: int}}\n",
    );
    let (_, good) = values(&dir, "test-app:\n  count: 1\n  defaults: {count: 2}\n");
    let mut runner = ReplayCommandRunner::default();
    let mut engine = Engine {
        prefs: &mut prefs,
        runner: &mut runner,
        clock: &clock,
        state: &mut state,
        state_dir: dir.path().into(),
        options: Options::default(),
        warnings: vec![],
    };
    let plan = engine.plan(&[recipe], &good, "diff").unwrap();
    assert_eq!(
        plan.apps[0].entries[0].actions[0].desired,
        Some(serde_json::json!(2))
    );
    assert!(engine
        .warnings
        .iter()
        .any(|w| w.contains("overrides root-bound")));
}

#[test]
fn deep_merge_file_preserves_unowned_keys_and_detects_drift() {
    let dir = TempDir::new().unwrap();
    let target = dir.path().join("settings.json");
    write(&target, "{\"owned\": 0, \"keep\": true}\n");
    let config=format!("  - kind: file\n    binds: settings\n    path: {}\n    format: json\n    merge: deep_merge\n",target.display());
    let recipe = loaded_recipe(&dir, &config);
    let (_, values) = values(&dir, "test-app:\n  settings: {owned: 1}\n");
    let mut state = State::default();
    state
        .apps
        .entry("test-app".into())
        .or_default()
        .entries
        .insert(
            "settings".into(),
            EntryState {
                checksum: Some(checksum(&fs::read(&target).unwrap())),
                applied_at: NOW.into(),
                ..Default::default()
            },
        );
    let mut prefs = FakePrefStore::default();
    let mut runner = ReplayCommandRunner::default();
    let clock = FixedClock(NOW.into());
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
    assert!(plan.apps[0].entries[0].drift.is_empty());
    let applied = engine.apply(std::slice::from_ref(&recipe), &values, plan);
    assert_eq!(applied.exit_code, 0);
    assert_eq!(
        serde_json::from_slice::<Value>(&fs::read(&target).unwrap()).unwrap(),
        serde_json::json!({"owned":1,"keep":true})
    );
    write(&target, "{\"owned\": 9, \"keep\": true}\n");
    let drift = engine.plan(&[recipe], &values, "diff").unwrap();
    assert_eq!(drift.apps[0].entries[0].drift[0].reason, "out_of_band");
}

#[derive(Default)]
struct SetRunner {
    members: BTreeSet<String>,
    recorded: Vec<String>,
    fail_on: Option<String>,
}
impl CommandRunner for SetRunner {
    fn run(&mut self, command: &str) -> Result<String> {
        self.recorded.push(command.into());
        if self.fail_on.as_deref() == Some(command) {
            return Err(anyhow!("injected command failure"));
        }
        if command == "list" {
            return Ok(self.members.iter().cloned().collect::<Vec<_>>().join("\n"));
        }
        if command.starts_with("deliver ") {
            return Ok(String::new());
        }
        if let Some(v) = command.strip_prefix("add ") {
            self.members.insert(v.trim_matches('\'').into());
            return Ok(String::new());
        }
        if let Some(v) = command.strip_prefix("del ") {
            self.members.remove(v.trim_matches('\''));
            return Ok(String::new());
        }
        Err(anyhow!("unknown command"))
    }

    fn run_owned(&mut self, program: &str, arguments: &[String]) -> Result<String> {
        self.run(&nix_me_apps::runner::render_owned_command(
            program, arguments,
        ))
    }
}

#[test]
fn command_set_converges_adds_and_deletes() {
    let dir = TempDir::new().unwrap();
    let recipe=loaded_recipe(&dir,"  - kind: command\n    name: extensions\n    list:\n      get: list\n      add: 'add {item}'\n      del: 'del {item}'\n    converges: full\n");
    let (_, values) = values(&dir, "test-app:\n  extensions: [new]\n");
    let mut prefs = FakePrefStore::default();
    let mut runner = SetRunner {
        members: ["old".into()].into(),
        ..Default::default()
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
    assert_eq!(plan.summary.adds, 1);
    assert_eq!(plan.summary.dels, 1);
    let applied = engine.apply(std::slice::from_ref(&recipe), &values, plan);
    assert_eq!(applied.exit_code, 0);
    assert_eq!(engine.runner.members, ["new".into()].into());
    assert_eq!(
        engine.plan(&[recipe], &values, "diff").unwrap().exit_code,
        0
    );
}

#[test]
fn manual_residue_uses_exit_three() {
    let dir = TempDir::new().unwrap();
    let recipe = loaded_recipe(&dir, "  - kind: manual\n    step: Sign in\n");
    let (_, values) = values(&dir, "test-app: {}\n");
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
        options: Options::default(),
        warnings: vec![],
    };
    let plan = engine.plan(&[recipe], &values, "diff").unwrap();
    assert_eq!(plan.exit_code, 3);
    assert_eq!(plan.summary.manual, 1);
}

#[test]
fn generated_import_is_delivered_only_after_reversible_work_succeeds() {
    let dir = TempDir::new().unwrap();
    let recipe=loaded_recipe(&dir,"  - kind: generated_import\n    source: profile.test-app.import\n    deliver: deliver {artifact}\n    confirm: one_click\n    converges: add_only\n    artifact:\n      pipeline:\n        - header: {bytes: 4, keep: false, template: SEVBRA==}\n        - gzip: {}\n        - json: {}\n");
    let (_, import_values) = values(&dir, "test-app:\n  import: {items: [one]}\n");
    let mut prefs = FakePrefStore::default();
    let mut runner = SetRunner::default();
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
        .plan(std::slice::from_ref(&recipe), &import_values, "diff")
        .unwrap();
    assert_eq!(plan.summary.materialize, 1);
    assert_eq!(plan.summary.manual, 1);
    let artifact = plan.apps[0].entries[0].actions[0].target.clone();
    let applied = engine.apply(std::slice::from_ref(&recipe), &import_values, plan);
    assert_eq!(applied.exit_code, 3);
    assert!(Path::new(&artifact).exists());
    assert_eq!(
        applied.apps[0].entries[0].actions[1].result.as_deref(),
        Some("delivery_requested")
    );
    assert!(engine
        .runner
        .recorded
        .iter()
        .any(|command| command.starts_with("deliver ")));
    assert!(!engine
        .warnings
        .iter()
        .any(|warning| warning.contains("generated_import delivery is not transaction-safe")));
    let retry = engine
        .plan(std::slice::from_ref(&recipe), &import_values, "diff")
        .unwrap();
    assert_eq!(retry.summary.materialize, 1);
    assert!(retry.apps[0].entries[0]
        .actions
        .iter()
        .any(|action| action.op == "deliver"));

    let recipe = loaded_recipe(
        &dir,
        "  - kind: command\n    name: extensions\n    list:\n      get: list\n      add: 'add {item}'\n      del: 'del {item}'\n    converges: full\n  - kind: generated_import\n    source: profile.test-app.import\n    deliver: deliver {artifact}\n    confirm: one_click\n    converges: add_only\n    artifact:\n      pipeline:\n        - json: {}\n",
    );
    let (_, values) = values(
        &dir,
        "test-app:\n  extensions: [new]\n  import: {items: [one]}\n",
    );
    let mut prefs = FakePrefStore::default();
    let mut runner = SetRunner {
        fail_on: Some("add new".into()),
        ..Default::default()
    };
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
    assert!(!engine
        .runner
        .recorded
        .iter()
        .any(|command| command.starts_with("deliver ")));
}

#[test]
fn shipped_raycast_pipeline_round_trips_plain_and_encrypted_envelopes() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let recipe_path = root.join("recipes/raycast.yaml");
    let values_path = root.join("values/raycast.yaml");
    if !recipe_path.is_file() || !values_path.is_file() {
        // The Nix package source contains engine/ only. Checkout CI exercises
        // this registry-level smoke test against the shipped recipe.
        return;
    }
    let recipe = load_recipe(&recipe_path).unwrap();
    let values = load_values(&[values_path]).unwrap();
    let profile = Value::Object(values.clone());
    let model = values["raycast"]["import"].clone();
    let pipeline = recipe
        .config
        .iter()
        .find_map(|entry| match entry {
            ConfigEntry::GeneratedImport(entry) => match &entry.artifact {
                Artifact::Pipeline { pipeline } => Some(pipeline),
                Artifact::Codec { .. } => None,
            },
            _ => None,
        })
        .expect("Raycast must retain its declarative import pipeline");

    for encrypt in [false, true] {
        let mut state = ArtifactState::default();
        state.optional_steps_applied.insert("1".into(), encrypt);
        let encoded =
            nix_me_apps::pipeline::encode(pipeline, &model, &profile, &mut state).unwrap();
        let decoded = nix_me_apps::pipeline::decode(
            pipeline,
            &encoded,
            &profile,
            &mut ArtifactState::default(),
        )
        .unwrap();
        assert_eq!(decoded, model);

        let corrupt = &encoded[..15.min(encoded.len())];
        assert!(nix_me_apps::pipeline::decode(
            pipeline,
            corrupt,
            &profile,
            &mut ArtifactState::default()
        )
        .is_err());
    }
}

#[test]
fn corrupt_state_is_preserved_not_repaired_in_place() {
    let dir = TempDir::new().unwrap();
    let path = dir.path().join("apps.json");
    write(&path, "{broken");
    let guard = StateGuard::acquire(&path, false, NOW).unwrap();
    assert!(guard.state.apps.is_empty());
    let names = fs::read_dir(dir.path())
        .unwrap()
        .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
        .collect::<Vec<_>>();
    assert!(names.iter().any(|n| n.starts_with("apps.json.corrupt-")));
}

#[test]
fn unsupported_state_version_is_rejected_without_mutation() {
    let dir = TempDir::new().unwrap();
    let path = dir.path().join("apps.json");
    let contents = r#"{"version":2,"updated_at":"future","apps":{}}"#;
    write(&path, contents);

    let error = StateGuard::acquire(&path, false, NOW)
        .err()
        .expect("future state versions must fail closed");
    assert!(error
        .to_string()
        .contains("unsupported app-state version 2"));
    assert_eq!(fs::read_to_string(&path).unwrap(), contents);

    let names = fs::read_dir(dir.path())
        .unwrap()
        .map(|entry| entry.unwrap().file_name().to_string_lossy().into_owned())
        .collect::<Vec<_>>();
    assert_eq!(names, vec!["apps.json"]);
}

#[test]
fn no_wait_refuses_a_second_state_lock() {
    let dir = TempDir::new().unwrap();
    let path = dir.path().join("apps.json");
    let _first = StateGuard::acquire(&path, false, NOW).unwrap();
    let error = StateGuard::acquire(&path, true, NOW)
        .err()
        .expect("second lock must fail");
    assert!(error.to_string().contains("another nix-me apps apply"));
}

#[test]
fn state_file_is_user_only() {
    let dir = TempDir::new().unwrap();
    let path = dir.path().join("apps.json");
    let mut guard = StateGuard::acquire(&path, false, NOW).unwrap();
    guard.save(NOW).unwrap();
    assert_eq!(
        fs::metadata(path).unwrap().permissions().mode() & 0o777,
        0o600
    );
}

#[test]
fn repository_recipes_pass_schema_and_semantic_validation() {
    let recipes = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../recipes");
    if !recipes.is_dir() {
        // The Nix package deliberately builds from engine/ only; checkout CI
        // includes the registry seed and exercises this validation path.
        return;
    }
    let mut loaded = 0;
    for entry in fs::read_dir(recipes).unwrap() {
        let path = entry.unwrap().path();
        if matches!(
            path.extension().and_then(|value| value.to_str()),
            Some("yaml" | "yml")
        ) {
            load_recipe(&path).unwrap_or_else(|error| panic!("{}: {error:#}", path.display()));
            loaded += 1;
        }
    }
    assert!(loaded >= 4);
}

#[test]
fn shipped_hiddenbar_recipe_converges_preferences_and_reports_manual_layout() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let recipe_path = root.join("recipes/hiddenbar.yaml");
    if !recipe_path.is_file() {
        // The Nix package source contains engine/ only. Checkout CI exercises
        // the complete registry recipe.
        return;
    }

    let directory = TempDir::new().unwrap();
    let mut recipe = load_recipe(&recipe_path).unwrap();
    recipe.detect = None;
    recipe.app_version = None;
    assert!(
        !recipe.sandboxed,
        "the Homebrew direct build is not sandboxed"
    );

    let (_, values) = values(
        &directory,
        r#"hiddenbar:
  isAutoStart: true
  isShowPreferences: false
  isAutoHide: true
  numberOfSecondForAutoHide: 5.0
  areSeparatorsHidden: false
  alwaysHiddenSectionEnabled: true
  useFullStatusBarOnExpandEnabled: false
  hoverToExpand: true
  AppleLanguages: [en]
  globalKey: AQID
"#,
    );
    let mut prefs = FakePrefStore::default();
    prefs.set(
        "com.dwarvesv.minimalbar",
        "smAppServiceMigrated",
        Host::Any,
        Value::Bool(true),
    );
    let mut runner = ReplayCommandRunner::default();
    let poke = poke_command(&recipe).unwrap();
    runner.outputs.insert(poke.clone(), Ok(String::new()));
    let clock = FixedClock(NOW.into());
    let mut state = State::default();
    let mut engine = Engine {
        prefs: &mut prefs,
        runner: &mut runner,
        clock: &clock,
        state: &mut state,
        state_dir: directory.path().join("state"),
        options: Options::default(),
        warnings: vec![],
    };

    let plan = engine
        .plan(std::slice::from_ref(&recipe), &values, "diff")
        .unwrap();
    assert_eq!(plan.exit_code, 2);
    assert_eq!(plan.summary.writes, 10);
    assert_eq!(plan.summary.manual, 1);
    assert_eq!(plan.apps[0].pokes, ["restart_app"]);

    let applied = engine.apply(std::slice::from_ref(&recipe), &values, plan);
    assert_eq!(applied.exit_code, 3);
    assert_eq!(engine.runner.recorded, [poke]);
    assert_eq!(
        engine.prefs.values.get(&(
            "com.dwarvesv.minimalbar".into(),
            Host::Any,
            "smAppServiceMigrated".into()
        )),
        Some(&Value::Bool(true)),
        "unowned migration state must be preserved"
    );

    let converged = engine.plan(&[recipe], &values, "diff").unwrap();
    assert_eq!(converged.exit_code, 3);
    assert_eq!(converged.summary.writes, 0);
    assert_eq!(converged.summary.manual, 1);
}

#[test]
fn local_top_200_catalog_is_complete_and_links_seed_recipes() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let catalog = root.join("catalog/homebrew-top-200-apps.json");
    let recipes = root.join("recipes");
    if !catalog.is_file() || !recipes.is_dir() {
        // The Nix package source contains engine/ only; checkout CI runs this.
        return;
    }
    let recipe_inputs = [recipes];
    let validation = nix_me_apps::catalog::validate(&catalog, &recipe_inputs).unwrap();
    assert!(validation.valid);
    assert_eq!(validation.applications, 200);
    assert_eq!(validation.local_recipes, 8);
    assert_eq!(validation.confidence.values().sum::<usize>(), 200);
    assert_eq!(validation.mechanisms.values().sum::<usize>(), 200);

    let metric = nix_me_apps::catalog::metric(&catalog, &recipe_inputs).unwrap();
    assert_eq!(metric.denominator, 200);
    assert_eq!(metric.behavior_mapped_apps, 200);
    assert_eq!(metric.zero_click_apps, 6);
    assert_eq!(metric.one_click_apps, 1);
    assert_eq!(metric.full_manual_apps, 1);
    assert_eq!(metric.uncovered_apps, 192);
}

#[test]
fn plan_json_surface_has_v1_shape() {
    let dir = TempDir::new().unwrap();
    let recipe_path = dir.path().join("test-app.yaml");
    write(
        &recipe_path,
        "schema_version: 1\nid: test-app\nname: Test App\nbundle_id: com.nix-me.test\nconfig:\n  - kind: defaults\n    domain: com.nix-me.test\n    keys:\n      enabled: {type: bool}\n      theme: {type: string}\n    unknown_keys: reject\n  - kind: manual\n    step: Sign in\napply:\n  poke: restart_app\nverified: null\n",
    );
    let recipe = load_recipe(&recipe_path).unwrap();
    let (_, values) = values(&dir, "test-app: {enabled: true, theme: dark}\n");
    let mut prefs = FakePrefStore::default();
    prefs.set("com.nix-me.test", "enabled", Host::Any, Value::Bool(false));
    prefs.set(
        "com.nix-me.test",
        "theme",
        Host::Any,
        Value::String("light".into()),
    );
    prefs
        .forced
        .insert(("com.nix-me.test".into(), "theme".into()), true);
    let mut runner = ReplayCommandRunner::default();
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
    let actual = serde_json::to_value(engine.plan(&[recipe], &values, "diff").unwrap()).unwrap();
    let expected: Value =
        serde_json::from_str(include_str!("../../fixtures/plan-v1.json")).unwrap();
    assert_eq!(actual, expected);
}
