use std::fs;
use std::io::Write;
use std::path::Path;
use std::process::Stdio;
use std::process::{Command, Output};

use serde_json::Value;
use tempfile::TempDir;

fn write(path: &Path, contents: &str) {
    fs::write(path, contents).unwrap();
}

fn run(dir: &TempDir, args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_nix-me-apps"))
        .args(args)
        .env("NIX_ME_STATE_DIR", dir.path().join("state"))
        .output()
        .unwrap()
}

fn run_with_stdin(dir: &TempDir, args: &[&str], input: &[u8]) -> Output {
    let mut child = Command::new(env!("CARGO_BIN_EXE_nix-me-apps"))
        .args(args)
        .env("NIX_ME_STATE_DIR", dir.path().join("state"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    child.stdin.take().unwrap().write_all(input).unwrap();
    child.wait_with_output().unwrap()
}

#[test]
fn apply_validation_error_is_exit_four_and_json_agrees() {
    let dir = TempDir::new().unwrap();
    let recipe = dir.path().join("invalid.yaml");
    let values = dir.path().join("values.yaml");
    write(&recipe, "schema_version: 1\nid: invalid\n");
    write(&values, "invalid: {}\n");

    let output = run(
        &dir,
        &[
            "apply",
            "--recipe",
            recipe.to_str().unwrap(),
            "--values",
            values.to_str().unwrap(),
            "--yes",
            "--json",
        ],
    );
    assert_eq!(output.status.code(), Some(4));
    let error: Value = serde_json::from_slice(&output.stderr).unwrap();
    assert_eq!(error["version"], 1);
    assert_eq!(error["exit_code"], 4);
}

#[test]
fn execution_failure_is_exit_five_and_json_agrees() {
    let dir = TempDir::new().unwrap();
    let recipe = dir.path().join("command.yaml");
    let values = dir.path().join("values.yaml");
    write(
        &recipe,
        "schema_version: 1\nid: command-test\nname: Command Test\nbundle_id: com.nix-me.test.command\nconfig:\n  - kind: command\n    name: items\n    list:\n      get: \"printf ''\"\n      add: \"false # {item}\"\n    converges: add_only\nverified: null\n",
    );
    write(&values, "command-test:\n  items: [new]\n");

    let output = run(
        &dir,
        &[
            "apply",
            "--recipe",
            recipe.to_str().unwrap(),
            "--values",
            values.to_str().unwrap(),
            "--yes",
            "--json",
        ],
    );
    assert_eq!(output.status.code(), Some(5));
    let plan: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(plan["exit_code"], 5);
    assert_eq!(
        plan["apps"][0]["entries"][0]["actions"][0]["result"],
        "failed"
    );
}

#[test]
fn no_exec_audits_resolved_commands_and_keeps_json_clean() {
    let dir = TempDir::new().unwrap();
    let recipe = dir.path().join("audit.yaml");
    let values = dir.path().join("values.yaml");
    write(
        &recipe,
        "schema_version: 1\nid: audit-test\nname: Audit Test\nbundle_id: com.nix-me.test.audit\nconfig:\n  - kind: command\n    name: items\n    list:\n      get: \"printf current\"\n      add: \"install-item {item}\"\n    converges: add_only\napply:\n  poke: script\n  poke_script: refresh-audit-test\nverified: null\n",
    );
    write(&values, "audit-test:\n  items: [new]\n");

    let output = run(
        &dir,
        &[
            "apply",
            "--recipe",
            recipe.to_str().unwrap(),
            "--values",
            values.to_str().unwrap(),
            "--yes",
            "--no-exec",
            "--json",
        ],
    );
    assert_eq!(output.status.code(), Some(2));
    let plan: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(plan["exit_code"], 2);
    let audit = String::from_utf8(output.stderr).unwrap();
    assert!(audit.contains("printf current"));
    assert!(audit.contains("install-item new"));
    assert!(audit.contains("refresh-audit-test"));
    assert!(!dir.path().join("state/apps.json").exists());
}

#[test]
fn declined_json_apply_still_emits_a_plan_with_the_process_exit_code() {
    let dir = TempDir::new().unwrap();
    let recipe = dir.path().join("decline.yaml");
    let values = dir.path().join("values.yaml");
    write(
        &recipe,
        "schema_version: 1\nid: decline-test\nname: Decline Test\nbundle_id: com.nix-me.test.decline\nconfig:\n  - kind: command\n    name: items\n    list:\n      get: \"printf ''\"\n      add: \"printf added\"\n    converges: add_only\nverified: null\n",
    );
    write(&values, "decline-test:\n  items: [new]\n");
    let output = run_with_stdin(
        &dir,
        &[
            "apply",
            "--recipe",
            recipe.to_str().unwrap(),
            "--values",
            values.to_str().unwrap(),
            "--json",
        ],
        b"n\n",
    );
    assert_eq!(output.status.code(), Some(2));
    let plan: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(plan["exit_code"], 2);
    assert_eq!(
        dir.path().join("state/apps.json").metadata().unwrap().len(),
        0
    );
}

#[test]
fn registry_validate_and_metric_are_machine_readable() {
    let dir = TempDir::new().unwrap();
    let recipes = dir.path().join("recipes");
    fs::create_dir(&recipes).unwrap();
    write(
        &recipes.join("example.yaml"),
        "schema_version: 1\nid: example\nname: Example\nbundle_id: com.example.App\nconfig:\n  - kind: defaults\n    domain: com.example.App\n    keys:\n      enabled: {type: bool}\nverified: null\n",
    );
    let recipe_arg = recipes.to_str().unwrap();
    let validation = run(
        &dir,
        &["registry", "validate", "--recipe", recipe_arg, "--json"],
    );
    assert!(validation.status.success());
    let validation: Value = serde_json::from_slice(&validation.stdout).unwrap();
    assert_eq!(validation["valid"], true);
    assert_eq!(validation["ids"], serde_json::json!(["example"]));

    let metric = run(
        &dir,
        &[
            "registry",
            "metric",
            "--recipe",
            recipe_arg,
            "--denominator",
            "200",
            "--json",
        ],
    );
    assert!(metric.status.success());
    let metric: Value = serde_json::from_slice(&metric.stdout).unwrap();
    assert_eq!(metric["zero_click_apps"], 1);
    assert_eq!(metric["uncovered_apps"], 199);
    assert_eq!(metric["zero_click_percent"], 0.5);
}

#[test]
fn capture_sniff_can_atomically_write_the_decoded_model() {
    let dir = TempDir::new().unwrap();
    let artifact = dir.path().join("settings.txt");
    let output = dir.path().join("decoded/settings.json");
    write(&artifact, "eyJjYXB0dXJlZCI6dHJ1ZX0=");
    let result = run(
        &dir,
        &[
            "capture",
            "--sniff",
            artifact.to_str().unwrap(),
            "--output",
            output.to_str().unwrap(),
            "--json",
        ],
    );
    assert!(result.status.success());
    let decoded: Value = serde_json::from_slice(&fs::read(output).unwrap()).unwrap();
    assert_eq!(decoded, serde_json::json!({"captured":true}));
}

#[test]
fn catalog_validation_and_metric_are_machine_readable() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let catalog = root.join("catalog/homebrew-top-200-apps.json");
    let recipes = root.join("recipes");
    if !catalog.is_file() || !recipes.is_dir() {
        return;
    }
    let dir = TempDir::new().unwrap();
    let catalog_arg = catalog.to_str().unwrap();
    let recipe_arg = recipes.to_str().unwrap();
    let validation = run(
        &dir,
        &[
            "registry",
            "catalog-validate",
            "--catalog",
            catalog_arg,
            "--recipe",
            recipe_arg,
            "--json",
        ],
    );
    assert!(validation.status.success());
    let validation: Value = serde_json::from_slice(&validation.stdout).unwrap();
    assert_eq!(validation["applications"], 200);
    assert_eq!(validation["local_recipes"], 4);

    let metric = run(
        &dir,
        &[
            "registry",
            "catalog-metric",
            "--catalog",
            catalog_arg,
            "--recipe",
            recipe_arg,
            "--json",
        ],
    );
    assert!(metric.status.success());
    let metric: Value = serde_json::from_slice(&metric.stdout).unwrap();
    assert_eq!(metric["behavior_mapped_apps"], 200);
    assert_eq!(metric["zero_click_percent"], 1.5);
}
