use std::fs;
use std::path::{Path, PathBuf};

use nix_me_apps::engine::{poke_command, Engine, Options};
use nix_me_apps::model::{load_recipe, load_values, ConfigEntry, Host, Recipe};
use nix_me_apps::prefs::{FakePrefStore, PrefStore};
use nix_me_apps::runner::{FixedClock, ReplayCommandRunner};
use nix_me_apps::state::State;
use serde_json::{json, Map, Value};
use tempfile::TempDir;

const NOW: &str = "2026-10-05T12:00:00Z";

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../../..")
        .canonicalize()
        .unwrap()
}

fn recipe(id: &str) -> Recipe {
    load_recipe(
        &repo_root()
            .join("packages/app-state/recipes")
            .join(format!("{id}.yaml")),
    )
    .unwrap()
}

fn values() -> Map<String, Value> {
    load_values(&[Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/values.yaml")]).unwrap()
}

fn retarget_file(recipe: &mut Recipe, target: &Path) {
    recipe.detect = None;
    let ConfigEntry::File(file) = &mut recipe.config[0] else {
        panic!("expected a file recipe")
    };
    file.path = target.display().to_string();
}

fn assert_file_converges(id: &str, initial: &str, expected: Value) {
    let directory = TempDir::new().unwrap();
    let target = directory.path().join(format!("{id}.json"));
    fs::write(&target, initial).unwrap();

    let mut recipe = recipe(id);
    retarget_file(&mut recipe, &target);
    assert!(recipe.verified.is_none());

    let values = values();
    let mut prefs = FakePrefStore::default();
    let mut runner = ReplayCommandRunner::default();
    let mut state = State::default();
    let clock = FixedClock(NOW.into());
    let mut engine = Engine {
        prefs: &mut prefs,
        runner: &mut runner,
        clock: &clock,
        state: &mut state,
        state_dir: directory.path().join("state"),
        options: Options {
            force: true,
            ..Options::default()
        },
        warnings: vec![],
    };

    let plan = engine.plan(&[recipe.clone()], &values, "diff").unwrap();
    assert_eq!(plan.exit_code, 2);
    assert_eq!(plan.apps[0].entries[0].actions[0].op, "merge_file");

    let applied = engine.apply(&[recipe.clone()], &values, plan);
    assert_eq!(applied.exit_code, 0);
    let actual: Value = serde_json::from_slice(&fs::read(&target).unwrap()).unwrap();
    assert_eq!(actual, expected);

    let converged = engine.plan(&[recipe], &values, "diff").unwrap();
    assert_eq!(converged.exit_code, 0);
    assert_eq!(converged.summary.files, 0);
}

#[test]
fn sublime_preferences_deep_merge_and_preserve_unowned_keys() {
    assert_file_converges(
        "sublime-text",
        "{\n  // retained semantically, formatting may normalize\n  \"font_size\": 15,\n  \"tab_size\": 8\n}\n",
        json!({
            "font_size": 15,
            "tab_size": 2,
            "translate_tabs_to_spaces": true,
            "trim_trailing_white_space_on_save": true
        }),
    );
}

#[test]
fn iterm_dynamic_profile_deep_merges_its_dedicated_file() {
    assert_file_converges(
        "iterm2",
        "{\"Preserved\": {\"owner\": \"user\"}, \"Profiles\": []}\n",
        json!({
            "Preserved": {"owner": "user"},
            "Profiles": [{
                "Name": "Nix Me",
                "Guid": "6a38647e-568f-4a44-9f2f-e2ac31265c86"
            }]
        }),
    );
}

#[test]
fn maccy_defaults_are_typed_preserve_unknown_keys_and_converge() {
    let directory = TempDir::new().unwrap();
    let mut recipe = recipe("maccy");
    recipe.detect = None;
    assert!(recipe.verified.is_none());

    let values = values();
    let mut prefs = FakePrefStore::default();
    prefs.set(
        "org.p0deje.Maccy",
        "SUEnableAutomaticChecks",
        Host::Any,
        Value::Bool(false),
    );
    let mut runner = ReplayCommandRunner::default();
    let poke = poke_command(&recipe).unwrap();
    runner.outputs.insert(poke.clone(), Ok(String::new()));
    let mut state = State::default();
    let clock = FixedClock(NOW.into());
    let mut engine = Engine {
        prefs: &mut prefs,
        runner: &mut runner,
        clock: &clock,
        state: &mut state,
        state_dir: directory.path().join("state"),
        options: Options::default(),
        warnings: vec![],
    };

    let plan = engine.plan(&[recipe.clone()], &values, "diff").unwrap();
    assert_eq!(plan.summary.writes, 5);
    assert_eq!(plan.apps[0].pokes, ["restart_app"]);

    let applied = engine.apply(&[recipe.clone()], &values, plan);
    assert_eq!(applied.exit_code, 0);
    assert_eq!(engine.runner.recorded, [poke]);
    assert_eq!(
        engine
            .prefs
            .read("org.p0deje.Maccy", "SUEnableAutomaticChecks", Host::Any,)
            .unwrap(),
        Some(Value::Bool(false))
    );

    let converged = engine.plan(&[recipe], &values, "diff").unwrap();
    assert_eq!(converged.exit_code, 0);
    assert_eq!(converged.summary.writes, 0);
}

#[test]
fn registered_recipes_without_values_are_inactive() {
    let mut recipes = [recipe("sublime-text"), recipe("iterm2"), recipe("maccy")];
    for recipe in &mut recipes {
        recipe.detect = None;
    }

    let directory = TempDir::new().unwrap();
    let mut prefs = FakePrefStore::default();
    let mut runner = ReplayCommandRunner::default();
    let mut state = State::default();
    let clock = FixedClock(NOW.into());
    let mut engine = Engine {
        prefs: &mut prefs,
        runner: &mut runner,
        clock: &clock,
        state: &mut state,
        state_dir: directory.path().join("state"),
        options: Options::default(),
        warnings: vec![],
    };

    let plan = engine.plan(&recipes, &Map::new(), "diff").unwrap();
    assert!(plan.apps.is_empty());
    assert_eq!(plan.exit_code, 0);
}

#[test]
fn maccy_rejects_a_wrongly_typed_owned_value() {
    let directory = TempDir::new().unwrap();
    let mut recipe = recipe("maccy");
    recipe.detect = None;
    let mut values = values();
    values["maccy"]["defaults"]["historySize"] = Value::String("many".into());

    let mut prefs = FakePrefStore::default();
    let mut runner = ReplayCommandRunner::default();
    let mut state = State::default();
    let clock = FixedClock(NOW.into());
    let mut engine = Engine {
        prefs: &mut prefs,
        runner: &mut runner,
        clock: &clock,
        state: &mut state,
        state_dir: directory.path().join("state"),
        options: Options::default(),
        warnings: vec![],
    };

    let error = engine.plan(&[recipe], &values, "diff").unwrap_err();
    assert!(error.to_string().contains("historySize has wrong type"));
}

#[test]
fn catalog_and_coverage_include_the_batch() {
    let root = repo_root().join("packages/app-state");
    let catalog = root.join("catalog/homebrew-top-200-apps.json");
    let recipes = [root.join("recipes")];

    let validation = nix_me_apps::catalog::validate(&catalog, &recipes).unwrap();
    assert!(validation.valid);
    assert_eq!(validation.applications, 200);
    assert_eq!(validation.local_recipes, 7);

    let metric = nix_me_apps::catalog::metric(&catalog, &recipes).unwrap();
    assert_eq!(metric.local_recipe_apps, 7);
    assert_eq!(metric.zero_click_apps, 6);
    assert_eq!(metric.one_click_apps, 1);
    assert_eq!(metric.uncovered_apps, 193);
    assert_eq!(metric.zero_click_percent, 3.0);
}
