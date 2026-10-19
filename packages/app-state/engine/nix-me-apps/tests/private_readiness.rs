use std::path::{Path, PathBuf};

use nix_me_apps::engine::{Engine, Options};
use nix_me_apps::model::{load_recipe, ConfigEntry};
use nix_me_apps::prefs::FakePrefStore;
use nix_me_apps::runner::{FixedClock, ReplayCommandRunner};
use nix_me_apps::state::State;
use serde_json::{json, Map, Value};
use tempfile::TempDir;

const NOW: &str = "2026-10-15T00:00:00Z";

fn recipe_path(id: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../recipes")
        .join(format!("{id}.yaml"))
}

fn configured_values(id: &str) -> Map<String, Value> {
    Map::from_iter([(id.to_owned(), json!({}))])
}

#[test]
fn private_readiness_markers_store_only_satisfied_state() {
    for (id, detection, marker) in [
        (
            "onepassword-cli",
            "command -v op >/dev/null 2>&1",
            "command -v op >/dev/null 2>&1 && op --version 2>/dev/null | grep -Eq '^2\\.' && op whoami --help >/dev/null 2>&1 && op whoami --format=json >/dev/null 2>&1",
        ),
        (
            "codex-cli",
            "command -v codex >/dev/null 2>&1",
            "command -v codex >/dev/null 2>&1 && codex login status --help >/dev/null 2>&1 && codex login status >/dev/null 2>&1",
        ),
    ] {
        let recipe = load_recipe(&recipe_path(id)).unwrap();
        let ConfigEntry::Manual(entry) = &recipe.config[0] else {
            panic!("{id} must remain a manual private boundary");
        };
        assert_eq!(entry.marker.as_ref().unwrap()["command"], marker);

        let mut runner = ReplayCommandRunner::default();
        runner
            .outputs
            .insert(detection.into(), Ok(String::new()));
        runner.outputs.insert(
            marker.into(),
            Ok(r#"{"email":"private@example.com","account":"secret"}"#.into()),
        );
        let mut prefs = FakePrefStore::default();
        let clock = FixedClock(NOW.into());
        let mut state = State::default();
        let state_dir = TempDir::new().unwrap();
        let mut engine = Engine {
            prefs: &mut prefs,
            runner: &mut runner,
            clock: &clock,
            state: &mut state,
            state_dir: state_dir.path().into(),
            options: Options::default(),
            warnings: vec![],
        };

        let plan = engine
            .plan(&[recipe], &configured_values(id), "diff")
            .unwrap();
        assert!(plan.checklist[0].satisfied);
        assert_eq!(plan.summary.manual, 0);
        let serialized = serde_json::to_string(&plan).unwrap();
        assert!(!serialized.contains("private@example.com"));
        assert!(!serialized.contains("secret"));
        assert_eq!(runner.recorded, [detection, marker]);
    }
}

#[test]
fn private_readiness_is_fail_closed_when_the_status_check_fails() {
    let id = "codex-cli";
    let detection = "command -v codex >/dev/null 2>&1";
    let marker = "command -v codex >/dev/null 2>&1 && codex login status --help >/dev/null 2>&1 && codex login status >/dev/null 2>&1";
    let recipe = load_recipe(&recipe_path(id)).unwrap();
    let mut runner = ReplayCommandRunner::default();
    runner.outputs.insert(detection.into(), Ok(String::new()));
    runner
        .outputs
        .insert(marker.into(), Err("not authenticated".into()));
    let mut prefs = FakePrefStore::default();
    let clock = FixedClock(NOW.into());
    let mut state = State::default();
    let state_dir = TempDir::new().unwrap();
    let mut engine = Engine {
        prefs: &mut prefs,
        runner: &mut runner,
        clock: &clock,
        state: &mut state,
        state_dir: state_dir.path().into(),
        options: Options::default(),
        warnings: vec![],
    };

    let plan = engine
        .plan(&[recipe], &configured_values(id), "diff")
        .unwrap();
    assert!(!plan.checklist[0].satisfied);
    assert_eq!(plan.summary.manual, 1);
    assert_eq!(plan.exit_code, 3);
}

#[test]
fn accessibility_fallbacks_remain_manual_and_request_no_engine_tcc_grants() {
    for id in [
        "adobe-creative-cloud",
        "autodesk-fusion",
        "bambu-connect",
        "elgato-camera-hub",
        "loom",
        "microsoft-teams",
        "telegram",
    ] {
        let recipe = load_recipe(&recipe_path(id)).unwrap();
        assert!(
            recipe.requires.is_empty(),
            "{id} has no executable AX action"
        );
        assert_eq!(recipe.config.len(), 1);
        let ConfigEntry::Manual(entry) = &recipe.config[0] else {
            panic!("{id} must fail closed as a manual recipe");
        };
        assert!(entry.marker.is_none());
        assert!(entry
            .doc
            .as_deref()
            .unwrap()
            .starts_with("No Accessibility action runs"));
    }
}
