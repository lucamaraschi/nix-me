use std::fs;
use std::path::{Path, PathBuf};

use nix_me_apps::model::{load_recipe, ConfigEntry};
use nix_me_apps::registry;
use nix_me_apps::runner::ReplayCommandRunner;
use tempfile::TempDir;

fn write_recipe(directory: &TempDir, body: &str) -> PathBuf {
    let path = directory.path().join("fixture.yaml");
    fs::write(&path, body).unwrap();
    path
}

fn valid_accessibility_recipe(version_gate: &str, config: &str) -> String {
    format!(
        r#"schema_version: 1
id: fixture
name: Fixture
bundle_id: com.example.Fixture
detect:
  app_path: /Applications/Fixture.app
requires: [accessibility]
app_version:
  source: bundle_short_version
{version_gate}
config:
{config}verified: null
"#
    )
}

fn bool_config() -> &'static str {
    "  - kind: accessibility\n    name: launch_at_login\n    type: bool\n    localization: en-US\n    window: {title: Settings}\n    control: {role: AXCheckBox, identifier: launchAtLogin}\n"
}

#[test]
fn schema_accepts_only_version_gated_typed_exact_selectors() {
    for version_gate in [
        "  supported_majors: [2]",
        "  supported_exact: [2.2.1-beta.2]",
    ] {
        let directory = TempDir::new().unwrap();
        let recipe = load_recipe(&write_recipe(
            &directory,
            &valid_accessibility_recipe(version_gate, bool_config()),
        ))
        .unwrap();
        assert!(matches!(recipe.config[0], ConfigEntry::Accessibility(_)));
    }
}

#[test]
fn semantic_validation_rejects_shell_version_sources_and_missing_permission() {
    let directory = TempDir::new().unwrap();
    let shell_version = valid_accessibility_recipe("  supported_majors: [2]", bool_config())
        .replace(
            "source: bundle_short_version",
            "command: /usr/bin/defaults read /Applications/Fixture.app/Contents/Info CFBundleShortVersionString",
        );
    assert!(load_recipe(&write_recipe(&directory, &shell_version))
        .unwrap_err()
        .to_string()
        .contains("structured bundle_short_version"));

    let no_permission = valid_accessibility_recipe("  supported_majors: [2]", bool_config())
        .replace("requires: [accessibility]", "requires: []");
    assert!(load_recipe(&write_recipe(&directory, &no_permission))
        .unwrap_err()
        .to_string()
        .contains("require the accessibility permission"));
}

#[test]
fn schema_cannot_represent_text_secure_or_fuzzy_controls() {
    for replacement in [
        "control: {role: AXTextField, identifier: launchAtLogin}",
        "control: {role: AXSecureTextField, identifier: launchAtLogin}",
        "control: {role: AXCheckBox, title: Launch at login}",
    ] {
        let directory = TempDir::new().unwrap();
        let body = valid_accessibility_recipe("  supported_majors: [2]", bool_config()).replace(
            "control: {role: AXCheckBox, identifier: launchAtLogin}",
            replacement,
        );
        assert!(load_recipe(&write_recipe(&directory, &body)).is_err());
    }
}

#[test]
fn enum_actions_require_a_closed_allowlist_and_popup_role() {
    for config in [
        "  - kind: accessibility\n    name: theme\n    type: enum\n    localization: en-US\n    window: {title: Settings}\n    control: {role: AXPopUpButton, identifier: theme}\n",
        "  - kind: accessibility\n    name: theme\n    type: enum\n    localization: en-US\n    window: {title: Settings}\n    control: {role: AXCheckBox, identifier: theme}\n    allowed_values: [Light, Dark]\n",
        "  - kind: accessibility\n    name: theme\n    type: enum\n    localization: en-US\n    window: {title: Settings}\n    control: {role: AXPopUpButton, identifier: theme}\n    allowed_values: [Dark, Dark]\n",
    ] {
        let directory = TempDir::new().unwrap();
        let body = valid_accessibility_recipe("  supported_majors: [2]", config);
        assert!(load_recipe(&write_recipe(&directory, &body)).is_err());
    }
}

#[test]
fn registry_exposes_accessibility_as_typed_capture_without_a_managed_path() {
    let directory = TempDir::new().unwrap();
    let path = write_recipe(
        &directory,
        &valid_accessibility_recipe("  supported_majors: [2]", bool_config()),
    );
    let mut runner = ReplayCommandRunner::default();
    let catalog = registry::catalog(&[path], &mut runner).unwrap();
    let application = &catalog.applications[0];
    assert_eq!(application.capture_kinds, ["accessibility"]);
    assert!(application.managed_paths.is_empty());
    assert_eq!(application.exportable_settings[0].kind, "accessibility");
    assert_eq!(
        application.exportable_settings[0].source,
        "com.example.Fixture::Settings::AXCheckBox#launchAtLogin"
    );
}

#[test]
fn shipped_w4_recipes_remain_manual_without_recorded_ui_fixtures() {
    for id in [
        "adobe-creative-cloud",
        "autodesk-fusion",
        "bambu-connect",
        "elgato-camera-hub",
        "loom",
        "microsoft-teams",
        "telegram",
    ] {
        let path = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../recipes")
            .join(format!("{id}.yaml"));
        let recipe = load_recipe(&path).unwrap();
        assert!(recipe.requires.is_empty(), "{id} must not request AX yet");
        assert!(recipe
            .config
            .iter()
            .all(|entry| matches!(entry, ConfigEntry::Manual(_))));
    }
}
