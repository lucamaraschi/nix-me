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

fn last_apply(dir: &TempDir) -> Value {
    serde_json::from_slice(&fs::read(dir.path().join("state/last-apply.json")).unwrap()).unwrap()
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
    assert_eq!(last_apply(&dir)["status"], "failed");
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
    assert_eq!(last_apply(&dir)["status"], "failed");
}

#[test]
fn successful_and_partial_applies_are_persisted_accurately() {
    let success_dir = TempDir::new().unwrap();
    let success_recipe = success_dir.path().join("success.yaml");
    let success_values = success_dir.path().join("values.yaml");
    write(
        &success_recipe,
        "schema_version: 1\nid: success-test\nname: Success Test\nbundle_id: com.nix-me.test.success\nconfig:\n  - kind: command\n    name: items\n    list:\n      get: \"printf ''\"\n      add: \"true # {item}\"\n    converges: add_only\nverified: null\n",
    );
    write(&success_values, "success-test:\n  items: [new]\n");
    let success = run(
        &success_dir,
        &[
            "apply",
            "--recipe",
            success_recipe.to_str().unwrap(),
            "--values",
            success_values.to_str().unwrap(),
            "--yes",
            "--json",
        ],
    );
    assert!(success.status.success());
    let persisted = last_apply(&success_dir);
    assert_eq!(persisted["version"], 1);
    assert_eq!(persisted["status"], "succeeded");
    assert_eq!(persisted["message"], "Applied 1 configured recipe");

    let partial_dir = TempDir::new().unwrap();
    let partial_recipe = partial_dir.path().join("partial.yaml");
    let partial_values = partial_dir.path().join("values.yaml");
    write(
        &partial_recipe,
        "schema_version: 1\nid: partial-test\nname: Partial Test\nbundle_id: com.nix-me.test.partial\nconfig:\n  - kind: command\n    name: items\n    list:\n      get: \"printf ''\"\n      add: \"test {item} = good\"\n    converges: add_only\nverified: null\n",
    );
    write(&partial_values, "partial-test:\n  items: [bad, good]\n");
    let partial = run(
        &partial_dir,
        &[
            "apply",
            "--recipe",
            partial_recipe.to_str().unwrap(),
            "--values",
            partial_values.to_str().unwrap(),
            "--yes",
            "--json",
        ],
    );
    assert_eq!(partial.status.code(), Some(5));
    assert_eq!(last_apply(&partial_dir)["status"], "partial");
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
    assert!(!dir.path().join("state/last-apply.json").exists());
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
    assert_eq!(last_apply(&dir)["status"], "declined");
}

#[test]
fn status_counts_configured_recipes_and_emits_json_only_on_request() {
    let dir = TempDir::new().unwrap();
    let configured = dir.path().join("configured.yaml");
    let available = dir.path().join("available.yaml");
    let values = dir.path().join("values.yaml");
    write(
        &configured,
        "schema_version: 1\nid: configured\nname: Configured\nbundle_id: com.example.configured\nconfig:\n  - kind: defaults\n    domain: com.example.configured\n    keys: {}\nverified: null\n",
    );
    write(
        &available,
        "schema_version: 1\nid: available\nname: Available\nbundle_id: com.example.available\nconfig:\n  - kind: defaults\n    domain: com.example.available\n    keys: {}\nverified:\n  macos: \"15.0\"\n  app: \"1.0\"\n  date: \"2026-10-05\"\n  harness: \"0.1.0\"\n",
    );
    write(&values, "configured: {}\nunknown: {}\n");

    let json = run(
        &dir,
        &[
            "status",
            "--recipe",
            configured.to_str().unwrap(),
            "--recipe",
            available.to_str().unwrap(),
            "--values",
            values.to_str().unwrap(),
            "--json",
        ],
    );
    assert!(json.status.success());
    let status: Value = serde_json::from_slice(&json.stdout).unwrap();
    assert_eq!(status["schemaVersion"], 1);
    assert_eq!(status["engine"]["available"], true);
    assert_eq!(status["engine"]["version"], env!("CARGO_PKG_VERSION"));
    assert_eq!(status["configuredRecipeCount"], 1);
    assert_eq!(status["driftCount"], 0);
    assert_eq!(status["manualResidueCount"], 0);
    assert_eq!(status["verification"]["verifiedRecipeCount"], 0);
    assert_eq!(status["verification"]["unverifiedRecipeCount"], 1);
    assert!(status["warnings"]
        .as_array()
        .unwrap()
        .iter()
        .any(|warning| warning == "The persisted app-state status is unavailable"));
    assert!(!dir.path().join("state/apps.json").exists());

    let yaml = run(
        &dir,
        &[
            "status",
            "--recipe",
            configured.to_str().unwrap(),
            "--recipe",
            available.to_str().unwrap(),
            "--values",
            values.to_str().unwrap(),
        ],
    );
    assert!(yaml.status.success());
    assert!(serde_json::from_slice::<Value>(&yaml.stdout).is_err());
    assert!(String::from_utf8(yaml.stdout)
        .unwrap()
        .starts_with("schemaVersion: 1\n"));
}

#[test]
fn status_does_not_execute_commands_or_mutate_malformed_state() {
    let dir = TempDir::new().unwrap();
    let recipe = dir.path().join("readonly.yaml");
    let values = dir.path().join("values.yaml");
    let marker = dir.path().join("command-ran");
    let state_dir = dir.path().join("state");
    fs::create_dir(&state_dir).unwrap();
    write(&state_dir.join("apps.json"), "{broken-apps");
    write(&state_dir.join("last-apply.json"), "{broken-last-apply");
    write(
        &recipe,
        &format!(
            "schema_version: 1\nid: readonly\nname: Read Only\nbundle_id: com.example.readonly\ndetect:\n  command: \"touch {}\"\nconfig:\n  - kind: command\n    name: items\n    list:\n      get: \"touch {}; printf current\"\n      add: \"true # {{item}}\"\n    converges: add_only\nverified: null\n",
            marker.display(),
            marker.display()
        ),
    );
    write(&values, "readonly:\n  items: [desired]\n");

    let output = run(
        &dir,
        &[
            "status",
            "--recipe",
            recipe.to_str().unwrap(),
            "--values",
            values.to_str().unwrap(),
            "--json",
        ],
    );
    assert!(output.status.success());
    let status: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert!(status["warnings"]
        .as_array()
        .unwrap()
        .iter()
        .any(|warning| warning == "The persisted app-state status is malformed"));
    assert!(status["warnings"]
        .as_array()
        .unwrap()
        .iter()
        .any(|warning| warning == "The last app-state apply status is malformed"));
    assert_eq!(
        fs::read_to_string(state_dir.join("apps.json")).unwrap(),
        "{broken-apps"
    );
    assert_eq!(
        fs::read_to_string(state_dir.join("last-apply.json")).unwrap(),
        "{broken-last-apply"
    );
    assert!(!marker.exists());
    assert_eq!(fs::read_dir(state_dir).unwrap().count(), 2);
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
            "--yes",
            "--json",
        ],
    );
    assert!(result.status.success());
    let decoded: Value = serde_json::from_slice(&fs::read(output).unwrap()).unwrap();
    assert_eq!(decoded, serde_json::json!({"captured":true}));
}

#[test]
fn capture_output_requires_consent_without_a_terminal() {
    let dir = TempDir::new().unwrap();
    let artifact = dir.path().join("settings.json");
    let output = dir.path().join("capture.json");
    write(&artifact, r#"{"enabled":true}"#);

    let result = run(
        &dir,
        &[
            "capture",
            "--sniff",
            artifact.to_str().unwrap(),
            "--output",
            output.to_str().unwrap(),
        ],
    );

    assert_eq!(result.status.code(), Some(4));
    assert!(!output.exists());
    let stderr = String::from_utf8(result.stderr).unwrap();
    assert!(stderr.contains("Capture review:"));
    assert!(stderr.contains("requires explicit consent in non-interactive mode"));
}

#[test]
fn capture_dry_run_is_non_interactive_and_does_not_write() {
    let dir = TempDir::new().unwrap();
    let artifact = dir.path().join("settings.json");
    let output = dir.path().join("capture.json");
    write(&artifact, r#"{"enabled":true}"#);

    let result = run(
        &dir,
        &[
            "capture",
            "--sniff",
            artifact.to_str().unwrap(),
            "--output",
            output.to_str().unwrap(),
            "--dry-run",
            "--json",
        ],
    );

    assert!(result.status.success());
    assert!(!output.exists());
    let stderr = String::from_utf8(result.stderr).unwrap();
    assert!(stderr.contains(r#""path": "$/enabled""#));
    assert!(stderr.contains("Preview only; nothing was written or committed."));
}

#[test]
fn capture_watch_cannot_commit_non_interactively_without_yes() {
    let dir = TempDir::new().unwrap();
    let artifact = dir.path().join("settings.json");
    let output = dir.path().join("capture.json");
    write(&artifact, r#"{"enabled":true}"#);

    let result = run(
        &dir,
        &[
            "capture",
            "--sniff",
            artifact.to_str().unwrap(),
            "--watch",
            "--output",
            output.to_str().unwrap(),
            "--commit",
        ],
    );

    assert_eq!(result.status.code(), Some(4));
    assert!(!output.exists());
    assert!(String::from_utf8(result.stderr)
        .unwrap()
        .contains("requires explicit consent in non-interactive mode"));
}

#[test]
fn capture_sniff_redacts_nested_secrets_by_default() {
    let dir = TempDir::new().unwrap();
    let artifact = dir.path().join("settings.json");
    write(
        &artifact,
        r#"{"account":{"password":"hidden"},"items":["0123456789abcdefghijklmnopqrstuv"]}"#,
    );

    let result = run(
        &dir,
        &["capture", "--sniff", artifact.to_str().unwrap(), "--json"],
    );

    assert!(result.status.success());
    let captured: Value = serde_json::from_slice(&result.stdout).unwrap();
    assert_eq!(
        captured["model"],
        serde_json::json!({"account":{},"items":[null]})
    );
    assert_eq!(captured["redaction"]["policy"], "default_closed");
    assert_eq!(captured["redaction"]["count"], 2);
}

#[test]
fn guided_capture_refuses_non_interactive_input() {
    let dir = TempDir::new().unwrap();
    let result = run(&dir, &["capture", "Example", "--domain", "com.example.App"]);

    assert_eq!(result.status.code(), Some(4));
    assert!(String::from_utf8(result.stderr)
        .unwrap()
        .contains("guided capture requires an interactive terminal"));
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
