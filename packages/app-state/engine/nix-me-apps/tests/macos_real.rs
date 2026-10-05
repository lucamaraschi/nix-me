#![cfg(target_os = "macos")]

use nix_me_apps::model::{Host, ValueType};
use nix_me_apps::prefs::{CfPrefStore, DefaultsCliStore, PrefStore};

struct ScratchDomain(String);
impl Drop for ScratchDomain {
    fn drop(&mut self) {
        let _ = std::process::Command::new("defaults")
            .args(["delete", &self.0])
            .status();
    }
}

// T2 is compiled on every macOS build and executed only by the mac-side harness.
// It touches a unique scratch domain and never a real application's preferences.
#[test]
#[ignore = "run on the macOS real-backend harness"]
fn cfpreferences_and_defaults_fallback_agree_on_scratch_values() {
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let domain = ScratchDomain(format!("com.nix-me.test-{}-{stamp}", std::process::id()));
    let mut cf = CfPrefStore;
    cf.write_typed(
        &domain.0,
        "bool",
        &serde_json::json!(true),
        Host::Any,
        ValueType::Bool,
    )
    .unwrap();
    cf.write_typed(
        &domain.0,
        "int",
        &serde_json::json!(42),
        Host::Any,
        ValueType::Int,
    )
    .unwrap();
    cf.write_typed(
        &domain.0,
        "float",
        &serde_json::json!(2.5),
        Host::Current,
        ValueType::Float,
    )
    .unwrap();
    for (key, value, value_type) in [
        ("string", serde_json::json!("hello"), ValueType::String),
        (
            "array",
            serde_json::json!(["one", 2, true]),
            ValueType::Array,
        ),
        (
            "dict",
            serde_json::json!({"nested":true,"count":2}),
            ValueType::Dict,
        ),
        ("data", serde_json::json!("AQID"), ValueType::Data),
        (
            "date",
            serde_json::json!("2026-09-06T18:00:00Z"),
            ValueType::Date,
        ),
    ] {
        cf.write_typed(&domain.0, key, &value, Host::Any, value_type)
            .unwrap();
    }
    cf.synchronize(&domain.0).unwrap();
    let cli = DefaultsCliStore;
    assert_eq!(
        cli.read(&domain.0, "bool", Host::Any).unwrap(),
        Some(serde_json::json!(true))
    );
    assert_eq!(
        cli.read(&domain.0, "int", Host::Any).unwrap(),
        Some(serde_json::json!(42))
    );
    assert_eq!(
        cli.read(&domain.0, "float", Host::Current).unwrap(),
        Some(serde_json::json!(2.5))
    );
    for (key, expected) in [
        ("string", serde_json::json!("hello")),
        ("array", serde_json::json!(["one", 2, true])),
        ("dict", serde_json::json!({"nested":true,"count":2})),
        ("data", serde_json::json!("AQID")),
        ("date", serde_json::json!("2026-09-06T18:00:00Z")),
    ] {
        assert_eq!(cli.read(&domain.0, key, Host::Any).unwrap(), Some(expected));
    }

    let cli_domain = ScratchDomain(format!(
        "com.nix-me.test-cli-{}-{stamp}",
        std::process::id()
    ));
    let mut cli = DefaultsCliStore;
    for (key, value, value_type) in [
        (
            "array",
            serde_json::json!(["one", 2, true]),
            ValueType::Array,
        ),
        (
            "dict",
            serde_json::json!({"nested":true,"count":2}),
            ValueType::Dict,
        ),
        ("data", serde_json::json!("AQID"), ValueType::Data),
        (
            "date",
            serde_json::json!("2026-09-06T18:00:00Z"),
            ValueType::Date,
        ),
    ] {
        cli.write_typed(&cli_domain.0, key, &value, Host::Any, value_type)
            .unwrap();
        assert_eq!(cf.read(&cli_domain.0, key, Host::Any).unwrap(), Some(value));
    }
}
