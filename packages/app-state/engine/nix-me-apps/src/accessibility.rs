use anyhow::{anyhow, bail, Context, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::model::{AccessibilityEntry, AccessibilityRole, AccessibilityValueType};
use crate::plan::Action;
use crate::runner::{render_owned_command, CommandRunner};

// Recipes provide only data selectors. The executable JXA implementation is owned by the
// engine so a recipe can never inject script or type arbitrary text into an application.
const JXA_PROGRAM: &str = r#"
ObjC.import("Foundation");

function fail(message) {
  throw new Error("nix-me AX: " + message);
}

function normalizedLocale() {
  const locale = ObjC.unwrap($.NSLocale.currentLocale.localeIdentifier);
  return String(locale).replace(/_/g, "-");
}

function attribute(element, name) {
  const matches = element.attributes.whose({ name: name })();
  if (matches.length !== 1) fail("expected exactly one " + name + " attribute");
  return matches[0].value();
}

function roleOf(element) {
  return String(attribute(element, "AXRole"));
}

function identifierOf(element) {
  return String(attribute(element, "AXIdentifier"));
}

function press(element) {
  const actions = element.actions.whose({ name: "AXPress" })();
  if (actions.length !== 1) fail("control does not expose exactly one AXPress action");
  actions[0].perform();
}

function readValue(control, request) {
  const raw = attribute(control, "AXValue");
  if (request.valueType === "bool") {
    if (raw === true || raw === 1 || raw === "1") return true;
    if (raw === false || raw === 0 || raw === "0") return false;
    fail("boolean control returned a non-boolean value");
  }
  const value = String(raw);
  if (request.allowedValues.indexOf(value) === -1) {
    fail("enum control returned a value outside the recipe allowlist");
  }
  return value;
}

function same(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

function findTarget(request) {
  if (normalizedLocale() !== request.localization) {
    fail("localization mismatch");
  }
  if (["AXCheckBox", "AXSwitch", "AXPopUpButton"].indexOf(request.controlRole) === -1) {
    fail("unsupported control role");
  }
  if (request.controlRole === "AXSecureTextField" || request.controlRole === "AXTextField") {
    fail("text and secure fields are forbidden");
  }

  const systemEvents = Application("System Events");
  const processes = systemEvents.applicationProcesses.whose({
    bundleIdentifier: request.bundleId
  })();
  if (processes.length !== 1) fail("expected exactly one running application process");
  const process = processes[0];
  const windows = process.windows.whose({ name: request.windowTitle })();
  if (windows.length !== 1) fail("expected exactly one window with the configured title");

  const controls = windows[0].entireContents().filter(function (element) {
    try {
      return roleOf(element) === request.controlRole &&
        identifierOf(element) === request.controlIdentifier;
    } catch (_) {
      return false;
    }
  });
  if (controls.length !== 1) fail("expected exactly one matching control");
  return { process: process, control: controls[0] };
}

function selectEnum(process, control, desired) {
  press(control);
  delay(0.1);
  const menuItems = process.entireContents().filter(function (element) {
    try {
      return roleOf(element) === "AXMenuItem" &&
        String(attribute(element, "AXTitle")) === desired;
    } catch (_) {
      return false;
    }
  });
  if (menuItems.length !== 1) fail("expected exactly one allowlisted enum menu item");
  press(menuItems[0]);
}

function run(argv) {
  if (argv.length !== 1) fail("expected one typed request");
  const request = JSON.parse(argv[0]);
  const target = findTarget(request);
  const current = readValue(target.control, request);

  if (request.mode === "inspect") {
    return JSON.stringify({ value: current });
  }
  if (request.mode !== "apply") fail("unsupported operation");
  if (!same(current, request.expected)) fail("current value does not match expected value");
  if (same(request.expected, request.desired)) fail("refusing a no-op mutation");

  target.process.frontmost = true;
  if (request.valueType === "bool") {
    press(target.control);
  } else {
    selectEnum(target.process, target.control, request.desired);
  }

  let readback = readValue(target.control, request);
  for (let attempt = 0; attempt < 20 && !same(readback, request.desired); attempt += 1) {
    delay(0.05);
    readback = readValue(target.control, request);
  }
  if (!same(readback, request.desired)) fail("post-action control state differs from desired value");
  return JSON.stringify({ value: readback });
}
"#;

#[derive(Debug, Clone, PartialEq)]
pub struct AccessibilityTransition {
    pub expected: Value,
    pub desired: Value,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TransitionState {
    Converged,
    NeedsApply,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct AccessibilityRequest<'a> {
    mode: &'a str,
    bundle_id: &'a str,
    localization: &'a str,
    window_title: &'a str,
    control_role: &'static str,
    control_identifier: &'a str,
    value_type: &'static str,
    allowed_values: &'a [String],
    #[serde(skip_serializing_if = "Option::is_none")]
    expected: Option<&'a Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    desired: Option<&'a Value>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct AccessibilityResponse {
    value: Value,
}

pub fn transition(entry: &AccessibilityEntry, model: &Value) -> Result<AccessibilityTransition> {
    let object = model
        .as_object()
        .ok_or_else(|| anyhow!("accessibility bind {} must be a map", entry.name))?;
    let unexpected = object
        .keys()
        .filter(|key| key.as_str() != "expected" && key.as_str() != "desired")
        .cloned()
        .collect::<Vec<_>>();
    if !unexpected.is_empty() {
        bail!(
            "accessibility bind {} has unknown transition fields: {}",
            entry.name,
            unexpected.join(", ")
        );
    }
    let expected = object
        .get("expected")
        .cloned()
        .ok_or_else(|| anyhow!("accessibility bind {} is missing expected", entry.name))?;
    let desired = object
        .get("desired")
        .cloned()
        .ok_or_else(|| anyhow!("accessibility bind {} is missing desired", entry.name))?;
    validate_value(entry, &expected).context("invalid expected Accessibility value")?;
    validate_value(entry, &desired).context("invalid desired Accessibility value")?;
    Ok(AccessibilityTransition { expected, desired })
}

pub fn classify_current(
    transition: &AccessibilityTransition,
    current: &Value,
) -> Result<TransitionState> {
    if current == &transition.desired {
        Ok(TransitionState::Converged)
    } else if current == &transition.expected {
        Ok(TransitionState::NeedsApply)
    } else {
        bail!("current Accessibility value matches neither expected nor desired")
    }
}

pub fn plan_action(
    bundle_id: &str,
    entry: &AccessibilityEntry,
    transition: &AccessibilityTransition,
    current: Value,
) -> Result<Option<Action>> {
    match classify_current(transition, &current)? {
        TransitionState::Converged => Ok(None),
        TransitionState::NeedsApply => Ok(Some(Action {
            op: "accessibility".into(),
            target: target(bundle_id, entry),
            current: Some(current),
            desired: Some(transition.desired.clone()),
            value_type: Some(entry.value_type.as_str().into()),
            result: None,
            error: None,
        })),
    }
}

fn validate_value(entry: &AccessibilityEntry, value: &Value) -> Result<()> {
    match entry.value_type {
        AccessibilityValueType::Bool if value.is_boolean() => Ok(()),
        AccessibilityValueType::Enum => {
            let value = value
                .as_str()
                .ok_or_else(|| anyhow!("enum Accessibility values must be strings"))?;
            if entry.allowed_values.iter().any(|allowed| allowed == value) {
                Ok(())
            } else {
                bail!("enum Accessibility value is outside the recipe allowlist")
            }
        }
        AccessibilityValueType::Bool => bail!("boolean Accessibility values must be booleans"),
    }
}

pub fn target(bundle_id: &str, entry: &AccessibilityEntry) -> String {
    format!(
        "{}::{}::{}#{}",
        bundle_id,
        entry.window.title,
        entry.control.role.as_str(),
        entry.control.identifier
    )
}

pub fn inspect_command(bundle_id: &str, entry: &AccessibilityEntry) -> Result<String> {
    let (program, arguments) = invocation(AccessibilityRequest {
        mode: "inspect",
        bundle_id,
        localization: &entry.localization,
        window_title: &entry.window.title,
        control_role: entry.control.role.as_str(),
        control_identifier: &entry.control.identifier,
        value_type: entry.value_type.as_str(),
        allowed_values: &entry.allowed_values,
        expected: None,
        desired: None,
    })?;
    Ok(render_owned_command(program, &arguments))
}

pub fn apply_command(
    bundle_id: &str,
    entry: &AccessibilityEntry,
    transition: &AccessibilityTransition,
) -> Result<String> {
    let (program, arguments) = invocation(AccessibilityRequest {
        mode: "apply",
        bundle_id,
        localization: &entry.localization,
        window_title: &entry.window.title,
        control_role: entry.control.role.as_str(),
        control_identifier: &entry.control.identifier,
        value_type: entry.value_type.as_str(),
        allowed_values: &entry.allowed_values,
        expected: Some(&transition.expected),
        desired: Some(&transition.desired),
    })?;
    Ok(render_owned_command(program, &arguments))
}

fn invocation(request: AccessibilityRequest<'_>) -> Result<(&'static str, Vec<String>)> {
    let request = serde_json::to_string(&request)?;
    Ok((
        "/usr/bin/osascript",
        vec![
            "-l".into(),
            "JavaScript".into(),
            "-e".into(),
            JXA_PROGRAM.into(),
            "--".into(),
            request,
        ],
    ))
}

fn inspect_invocation(
    bundle_id: &str,
    entry: &AccessibilityEntry,
) -> Result<(&'static str, Vec<String>)> {
    invocation(AccessibilityRequest {
        mode: "inspect",
        bundle_id,
        localization: &entry.localization,
        window_title: &entry.window.title,
        control_role: entry.control.role.as_str(),
        control_identifier: &entry.control.identifier,
        value_type: entry.value_type.as_str(),
        allowed_values: &entry.allowed_values,
        expected: None,
        desired: None,
    })
}

fn apply_invocation(
    bundle_id: &str,
    entry: &AccessibilityEntry,
    transition: &AccessibilityTransition,
) -> Result<(&'static str, Vec<String>)> {
    invocation(AccessibilityRequest {
        mode: "apply",
        bundle_id,
        localization: &entry.localization,
        window_title: &entry.window.title,
        control_role: entry.control.role.as_str(),
        control_identifier: &entry.control.identifier,
        value_type: entry.value_type.as_str(),
        allowed_values: &entry.allowed_values,
        expected: Some(&transition.expected),
        desired: Some(&transition.desired),
    })
}

pub fn inspect<R: CommandRunner>(
    runner: &mut R,
    bundle_id: &str,
    entry: &AccessibilityEntry,
) -> Result<Value> {
    let (program, arguments) = inspect_invocation(bundle_id, entry)?;
    let output = runner.run_owned(program, &arguments)?;
    parse_inspection(entry, &output)
}

pub fn inspect_for_plan<R: CommandRunner>(
    runner: &mut R,
    bundle_id: &str,
    entry: &AccessibilityEntry,
    dry_run: bool,
    expected: &Value,
) -> Result<Value> {
    if !dry_run {
        return inspect(runner, bundle_id, entry);
    }
    let (program, arguments) = inspect_invocation(bundle_id, entry)?;
    runner.run_owned(program, &arguments)?;
    Ok(expected.clone())
}

pub fn parse_inspection(entry: &AccessibilityEntry, output: &str) -> Result<Value> {
    let response: AccessibilityResponse =
        serde_json::from_str(output.trim()).context("decode Accessibility inspection result")?;
    validate_value(entry, &response.value).context("invalid Accessibility inspection result")?;
    Ok(response.value)
}

pub fn apply<R: CommandRunner>(
    runner: &mut R,
    bundle_id: &str,
    entry: &AccessibilityEntry,
    transition: &AccessibilityTransition,
) -> Result<()> {
    if transition.expected == transition.desired {
        bail!("refusing a no-op Accessibility mutation");
    }
    let result = run_apply_once(runner, bundle_id, entry, transition);
    if let Err(error) = result {
        recover_after_failure(runner, bundle_id, entry, transition)
            .context("Accessibility apply failed and recovery could not prove rollback")?;
        return Err(error).context("Accessibility apply failed; original state was verified");
    }
    Ok(())
}

fn run_apply_once<R: CommandRunner>(
    runner: &mut R,
    bundle_id: &str,
    entry: &AccessibilityEntry,
    transition: &AccessibilityTransition,
) -> Result<()> {
    let (program, arguments) = apply_invocation(bundle_id, entry, transition)?;
    let output = runner.run_owned(program, &arguments)?;
    let response: AccessibilityResponse =
        serde_json::from_str(output.trim()).context("decode Accessibility apply result")?;
    validate_value(entry, &response.value).context("invalid Accessibility read-back result")?;
    if response.value != transition.desired {
        bail!("Accessibility semantic read-back differs from requested value");
    }
    Ok(())
}

fn recover_after_failure<R: CommandRunner>(
    runner: &mut R,
    bundle_id: &str,
    entry: &AccessibilityEntry,
    transition: &AccessibilityTransition,
) -> Result<()> {
    let current = inspect(runner, bundle_id, entry)
        .context("could not inspect control state after failed Accessibility action")?;
    if current == transition.expected {
        return Ok(());
    }
    if current != transition.desired {
        bail!("control state after failure matches neither expected nor desired");
    }

    let rollback = AccessibilityTransition {
        expected: transition.desired.clone(),
        desired: transition.expected.clone(),
    };
    run_apply_once(runner, bundle_id, entry, &rollback)
        .context("reverse Accessibility transition failed")?;
    let verified =
        inspect(runner, bundle_id, entry).context("could not verify Accessibility rollback")?;
    if verified != transition.expected {
        bail!("Accessibility rollback read-back differs from original value");
    }
    Ok(())
}

impl AccessibilityRole {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::CheckBox => "AXCheckBox",
            Self::Switch => "AXSwitch",
            Self::PopUpButton => "AXPopUpButton",
        }
    }
}

impl AccessibilityValueType {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Bool => "bool",
            Self::Enum => "enum",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{AccessibilityControl, AccessibilityWindow, Confirm};
    use crate::runner::{CommandRunner, RealCommandRunner, ReplayCommandRunner};
    use anyhow::{anyhow, Result};
    use serde_json::json;
    use std::collections::VecDeque;

    fn bool_entry() -> AccessibilityEntry {
        AccessibilityEntry {
            name: "launch_at_login".into(),
            value_type: AccessibilityValueType::Bool,
            localization: "en-US".into(),
            window: AccessibilityWindow {
                title: "Settings".into(),
            },
            control: AccessibilityControl {
                role: AccessibilityRole::CheckBox,
                identifier: "launchAtLogin".into(),
            },
            allowed_values: vec![],
            confirm: Confirm::OneClick,
        }
    }

    #[test]
    fn transition_is_typed_default_closed_and_has_no_free_text_surface() {
        let entry = bool_entry();
        let parsed = transition(&entry, &json!({"expected":false,"desired":true})).unwrap();
        assert_eq!(parsed.expected, json!(false));
        assert_eq!(parsed.desired, json!(true));
        assert!(transition(&entry, &json!({"expected":"no","desired":true})).is_err());
        assert!(transition(
            &entry,
            &json!({"expected":false,"desired":true,"script":"arbitrary"})
        )
        .is_err());
        assert_eq!(
            classify_current(&parsed, &json!(false)).unwrap(),
            TransitionState::NeedsApply
        );
        assert_eq!(
            classify_current(&parsed, &json!(true)).unwrap(),
            TransitionState::Converged
        );
        assert!(classify_current(&parsed, &json!(null)).is_err());
        let action = plan_action("com.example.App", &entry, &parsed, json!(false))
            .unwrap()
            .unwrap();
        assert_eq!(action.op, "accessibility");
        assert_eq!(action.current, Some(json!(false)));
        assert_eq!(action.desired, Some(json!(true)));
        assert_eq!(action.value_type.as_deref(), Some("bool"));
        assert!(plan_action("com.example.App", &entry, &parsed, json!(true))
            .unwrap()
            .is_none());
    }

    #[test]
    fn replay_inspection_and_apply_require_typed_semantic_readback() {
        let entry = bool_entry();
        let transition = transition(&entry, &json!({"expected":false,"desired":true})).unwrap();
        let inspect_command = inspect_command("com.example.App", &entry).unwrap();
        let apply_command = apply_command("com.example.App", &entry, &transition).unwrap();
        let mut runner = ReplayCommandRunner::default();
        runner
            .outputs
            .insert(inspect_command, Ok(r#"{"value":false}"#.into()));
        runner
            .outputs
            .insert(apply_command.clone(), Ok(r#"{"value":true}"#.into()));

        assert_eq!(
            inspect(&mut runner, "com.example.App", &entry).unwrap(),
            json!(false)
        );
        apply(&mut runner, "com.example.App", &entry, &transition).unwrap();

        runner
            .outputs
            .insert(apply_command, Ok(r#"{"value":false}"#.into()));
        assert!(apply(&mut runner, "com.example.App", &entry, &transition).is_err());
    }

    #[test]
    fn generated_jxa_is_owned_and_request_data_is_shell_quoted() {
        let entry = bool_entry();
        let command = inspect_command("com.example.App", &entry).unwrap();
        assert!(command.starts_with("/usr/bin/osascript -l JavaScript -e "));
        assert!(command.contains("text and secure fields are forbidden"));
        assert!(command.contains("current value does not match expected value"));
        assert!(!command.contains("launchAtLogin();"));
    }

    #[test]
    fn dry_run_records_owned_invocation_without_inspecting_ui() {
        let entry = bool_entry();
        let mut runner = RealCommandRunner {
            no_exec: true,
            ..RealCommandRunner::default()
        };
        let value =
            inspect_for_plan(&mut runner, "com.example.App", &entry, true, &json!(false)).unwrap();
        assert_eq!(value, json!(false));
        assert_eq!(runner.recorded.len(), 1);
        assert_eq!(
            runner.recorded[0],
            inspect_command("com.example.App", &entry).unwrap()
        );
    }

    struct SequenceRunner {
        outputs: VecDeque<Result<String>>,
        recorded: Vec<String>,
    }

    impl CommandRunner for SequenceRunner {
        fn run(&mut self, command: &str) -> Result<String> {
            self.recorded.push(command.into());
            self.outputs
                .pop_front()
                .unwrap_or_else(|| Err(anyhow!("missing replay response")))
        }

        fn run_owned(&mut self, program: &str, arguments: &[String]) -> Result<String> {
            self.run(&crate::runner::render_owned_command(program, arguments))
        }
    }

    #[test]
    fn failed_mutation_reverses_and_verifies_rollback() {
        let entry = bool_entry();
        let transition = transition(&entry, &json!({"expected":false,"desired":true})).unwrap();
        let mut runner = SequenceRunner {
            outputs: VecDeque::from([
                Err(anyhow!("post-action verification failed")),
                Ok(r#"{"value":true}"#.into()),
                Ok(r#"{"value":false}"#.into()),
                Ok(r#"{"value":false}"#.into()),
            ]),
            recorded: vec![],
        };

        let error = apply(&mut runner, "com.example.App", &entry, &transition)
            .unwrap_err()
            .to_string();
        assert!(error.contains("original state was verified"));
        assert_eq!(runner.recorded.len(), 4);
        assert!(runner.recorded[2].contains(r#""expected":true"#));
        assert!(runner.recorded[2].contains(r#""desired":false"#));
    }

    #[test]
    fn rollback_failure_is_never_reported_as_safe() {
        let entry = bool_entry();
        let transition = transition(&entry, &json!({"expected":false,"desired":true})).unwrap();
        let mut runner = SequenceRunner {
            outputs: VecDeque::from([
                Err(anyhow!("mutation failed")),
                Ok(r#"{"value":true}"#.into()),
                Ok(r#"{"value":false}"#.into()),
                Ok(r#"{"value":true}"#.into()),
            ]),
            recorded: vec![],
        };

        let error = apply(&mut runner, "com.example.App", &entry, &transition)
            .unwrap_err()
            .to_string();
        assert!(error.contains("recovery could not prove rollback"));
    }
}
