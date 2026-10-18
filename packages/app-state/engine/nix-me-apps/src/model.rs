use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use anyhow::{anyhow, bail, Context, Result};
use jsonschema::{Draft, JSONSchema};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

#[derive(Debug, Clone, Deserialize)]
pub struct Recipe {
    pub schema_version: u32,
    pub id: String,
    pub name: String,
    pub bundle_id: String,
    #[serde(default)]
    pub install: Option<Value>,
    #[serde(default)]
    pub detect: Option<Detect>,
    #[serde(default)]
    pub sandboxed: bool,
    #[serde(default)]
    pub requires: Vec<String>,
    #[serde(default)]
    pub app_version: Option<AppVersion>,
    pub config: Vec<ConfigEntry>,
    #[serde(default)]
    pub apply: ApplyPolicy,
    #[serde(default)]
    pub verified: Option<Verified>,
    #[serde(default)]
    pub maintainers: Vec<String>,
    #[serde(skip)]
    pub source_path: PathBuf,
}

#[derive(Debug, Clone, Deserialize)]
pub struct AppVersion {
    pub command: Option<String>,
    pub source: Option<AppVersionSource>,
    #[serde(default)]
    pub supported_majors: Vec<u64>,
    #[serde(default)]
    pub supported_exact: Vec<String>,
}

#[derive(Debug, Clone, Copy, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum AppVersionSource {
    BundleShortVersion,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Detect {
    pub app_path: Option<String>,
    pub command: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Verified {
    pub macos: String,
    pub app: String,
    pub date: String,
    pub harness: String,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct ApplyPolicy {
    #[serde(default)]
    pub poke: Poke,
    pub poke_script: Option<String>,
    #[serde(default)]
    pub unsafe_to_kill: bool,
}

#[derive(Debug, Clone, Copy, Default, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Poke {
    #[default]
    None,
    Cfprefsd,
    RestartApp,
    Script,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum ConfigEntry {
    Defaults(DefaultsEntry),
    File(FileEntry),
    Command(CommandEntry),
    CommandValue(CommandValueEntry),
    Accessibility(AccessibilityEntry),
    GeneratedImport(GeneratedImportEntry),
    Manual(ManualEntry),
}

#[derive(Debug, Clone, Deserialize)]
pub struct DefaultsEntry {
    pub domain: String,
    #[serde(default)]
    pub keys: BTreeMap<String, KeySchema>,
    #[serde(default)]
    pub unknown_keys: UnknownKeys,
    #[serde(default)]
    pub confirm: Confirm,
    pub binds: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct KeySchema {
    #[serde(rename = "type")]
    pub value_type: ValueType,
    pub ui: Option<String>,
    pub doc: Option<String>,
    #[serde(default)]
    pub host: Host,
}

#[derive(Debug, Clone, Copy, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ValueType {
    Bool,
    Int,
    Float,
    String,
    Array,
    Dict,
    Data,
    Date,
}

impl ValueType {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Bool => "bool",
            Self::Int => "int",
            Self::Float => "float",
            Self::String => "string",
            Self::Array => "array",
            Self::Dict => "dict",
            Self::Data => "data",
            Self::Date => "date",
        }
    }
}

#[derive(Debug, Clone, Copy, Default, Deserialize, Serialize, PartialEq, Eq, PartialOrd, Ord)]
#[serde(rename_all = "snake_case")]
pub enum Host {
    #[default]
    Any,
    Current,
}

#[derive(Debug, Clone, Copy, Default, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum UnknownKeys {
    #[default]
    Passthrough,
    Reject,
}

#[derive(Debug, Clone, Deserialize)]
pub struct FileEntry {
    pub path: String,
    pub format: FileFormat,
    #[serde(default)]
    pub export: FileExport,
    #[serde(default)]
    pub merge: Merge,
    #[serde(default)]
    pub paths: Option<PathPolicy>,
    #[serde(default)]
    pub checks: FileChecks,
    #[serde(default = "default_mode")]
    pub mode: String,
    #[serde(default)]
    pub confirm: Confirm,
    pub binds: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct PathPolicy {
    pub allow: Vec<String>,
    #[serde(default)]
    pub sensitive: Vec<String>,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct FileChecks {
    pub preflight: Option<String>,
    pub verify: Option<String>,
}
fn default_mode() -> String {
    "0644".into()
}

#[derive(Debug, Clone, Copy, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum FileFormat {
    Text,
    Json,
    Jsonc,
    Toml,
    Yaml,
    Plist,
    Ini,
    KeyValue,
    QsettingsXml,
}

#[derive(Debug, Clone, Copy, Default, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum FileExport {
    #[default]
    None,
    ReviewedText,
}

#[derive(Debug, Clone, Copy, Default, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Merge {
    #[default]
    Replace,
    DeepMerge,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CommandEntry {
    pub name: String,
    pub list: CommandTriple,
    #[serde(default)]
    pub converges: Converges,
    #[serde(default)]
    pub confirm: Confirm,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CommandTriple {
    pub get: String,
    pub add: String,
    pub del: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CommandValueEntry {
    pub name: String,
    #[serde(rename = "type")]
    pub value_type: ValueType,
    pub get: OwnedCommand,
    pub set: OwnedCommand,
    #[serde(default)]
    pub confirm: Confirm,
}

#[derive(Debug, Clone, Deserialize)]
pub struct OwnedCommand {
    pub executable: String,
    #[serde(default)]
    pub arguments: Vec<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct AccessibilityEntry {
    pub name: String,
    #[serde(rename = "type")]
    pub value_type: AccessibilityValueType,
    pub localization: String,
    pub window: AccessibilityWindow,
    pub control: AccessibilityControl,
    #[serde(default)]
    pub allowed_values: Vec<String>,
    #[serde(default = "one_click")]
    pub confirm: Confirm,
}

#[derive(Debug, Clone, Deserialize)]
pub struct AccessibilityWindow {
    pub title: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct AccessibilityControl {
    pub role: AccessibilityRole,
    pub identifier: String,
}

#[derive(Debug, Clone, Copy, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum AccessibilityValueType {
    Bool,
    Enum,
}

#[derive(Debug, Clone, Copy, Deserialize, PartialEq, Eq)]
pub enum AccessibilityRole {
    #[serde(rename = "AXCheckBox")]
    CheckBox,
    #[serde(rename = "AXSwitch")]
    Switch,
    #[serde(rename = "AXPopUpButton")]
    PopUpButton,
}

#[derive(Debug, Clone, Copy, Default, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Converges {
    #[default]
    Full,
    AddOnly,
}

#[derive(Debug, Clone, Deserialize)]
pub struct GeneratedImportEntry {
    pub source: String,
    pub deliver: String,
    pub artifact: Artifact,
    #[serde(default)]
    pub converges: Converges,
    #[serde(default = "one_click")]
    pub confirm: Confirm,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(untagged)]
pub enum Artifact {
    Pipeline {
        pipeline: Vec<serde_yaml::Value>,
    },
    Codec {
        codec: String,
        codec_version: String,
    },
}

#[derive(Debug, Clone, Deserialize)]
pub struct ManualEntry {
    pub step: String,
    pub doc: Option<String>,
    pub marker: Option<serde_yaml::Value>,
    #[serde(default = "full_manual")]
    pub confirm: Confirm,
}

#[derive(Debug, Clone, Copy, Default, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Confirm {
    #[default]
    None,
    OneClick,
    FullManual,
}
fn one_click() -> Confirm {
    Confirm::OneClick
}
fn full_manual() -> Confirm {
    Confirm::FullManual
}

impl ConfigEntry {
    pub fn kind(&self) -> &'static str {
        match self {
            Self::Defaults(_) => "defaults",
            Self::File(_) => "file",
            Self::Command(_) => "command",
            Self::CommandValue(_) => "command_value",
            Self::Accessibility(_) => "accessibility",
            Self::GeneratedImport(_) => "generated_import",
            Self::Manual(_) => "manual",
        }
    }
    pub fn bind(&self) -> Option<String> {
        match self {
            Self::Defaults(e) => Some(e.binds.clone().unwrap_or_else(|| "defaults".into())),
            Self::File(e) => Some(e.binds.clone().unwrap_or_else(|| "file".into())),
            Self::Command(e) => Some(e.name.clone()),
            Self::CommandValue(e) => Some(e.name.clone()),
            Self::Accessibility(e) => Some(e.name.clone()),
            Self::GeneratedImport(e) => Some(e.source.clone()),
            Self::Manual(_) => None,
        }
    }
    pub fn confirm(&self) -> Confirm {
        match self {
            Self::Defaults(e) => e.confirm,
            Self::File(e) => e.confirm,
            Self::Command(e) => e.confirm,
            Self::CommandValue(e) => e.confirm,
            Self::Accessibility(e) => e.confirm,
            Self::GeneratedImport(e) => e.confirm,
            Self::Manual(e) => e.confirm,
        }
    }
}

pub fn load_recipe(path: &Path) -> Result<Recipe> {
    let text =
        std::fs::read_to_string(path).with_context(|| format!("read recipe {}", path.display()))?;
    let yaml_value: serde_yaml::Value = serde_yaml::from_str(&text)
        .with_context(|| format!("parse YAML recipe {}", path.display()))?;
    let json_value = serde_json::to_value(yaml_value)?;
    decode_recipe_value(json_value, path)
}

pub(crate) fn decode_recipe_value(json_value: Value, path: &Path) -> Result<Recipe> {
    let schema: Value = serde_json::from_str(include_str!("../../recipe.schema.json"))?;
    let compiled = JSONSchema::options()
        .with_draft(Draft::Draft7)
        .compile(&schema)
        .map_err(|e| anyhow!("compile embedded recipe schema: {e}"))?;
    if let Err(errors) = compiled.validate(&json_value) {
        let details = errors
            .map(|e| format!("{}: {}", e.instance_path, e))
            .collect::<Vec<_>>()
            .join("; ");
        bail!(
            "recipe validation failed for {}: {}",
            path.display(),
            details
        );
    }
    let mut recipe: Recipe = serde_json::from_value(json_value)
        .with_context(|| format!("decode recipe {}", path.display()))?;
    recipe.source_path = path.to_path_buf();
    validate_semantics(&recipe)?;
    Ok(recipe)
}

pub fn validate_semantics(recipe: &Recipe) -> Result<()> {
    if recipe.sandboxed {
        let mut components = Path::new(&recipe.bundle_id).components();
        if !matches!(components.next(), Some(std::path::Component::Normal(_)))
            || components.next().is_some()
        {
            bail!(
                "recipe {}: sandboxed bundle_id must be one safe path component",
                recipe.id
            );
        }
    }
    let mut binds = BTreeMap::<String, usize>::new();
    for (index, entry) in recipe.config.iter().enumerate() {
        if let Some(bind) = entry.bind() {
            if let Some(first) = binds.insert(bind.clone(), index) {
                bail!(
                    "recipe {} has duplicate effective bind name '{}' at config entries {} and {}",
                    recipe.id,
                    bind,
                    first,
                    index
                );
            }
        }
        if let ConfigEntry::File(file) = entry {
            if recipe.sandboxed {
                let path = Path::new(&file.path);
                if path.is_absolute()
                    || file.path == "~"
                    || file.path.starts_with("~/")
                    || path
                        .components()
                        .any(|component| !matches!(component, std::path::Component::Normal(_)))
                {
                    bail!(
                        "recipe {}: sandboxed file paths must be relative, normalized container paths",
                        recipe.id
                    );
                }
            }
            if file.merge == Merge::DeepMerge && file.format == FileFormat::Text {
                bail!("recipe {}: deep_merge is invalid for text files", recipe.id);
            }
            if file.export == FileExport::ReviewedText && file.format != FileFormat::Text {
                bail!(
                    "recipe {}: reviewed_text export is only valid for text files",
                    recipe.id
                );
            }
            if matches!(
                file.format,
                FileFormat::Ini | FileFormat::KeyValue | FileFormat::QsettingsXml
            ) && file.paths.is_none()
            {
                bail!(
                    "recipe {}: {} files require an explicit path allowlist",
                    recipe.id,
                    match file.format {
                        FileFormat::Ini => "ini",
                        FileFormat::KeyValue => "key_value",
                        FileFormat::QsettingsXml => "qsettings_xml",
                        _ => unreachable!(),
                    }
                );
            }
            if file.paths.is_some() && file.format == FileFormat::Text {
                bail!(
                    "recipe {}: path policies are invalid for reviewed text files",
                    recipe.id
                );
            }
            if let Some(paths) = &file.paths {
                nix_me_codec::json::validate_allowlist(&paths.allow).with_context(|| {
                    format!("recipe {} has an invalid path allowlist", recipe.id)
                })?;
                nix_me_codec::json::assert_disjoint(&paths.allow, &paths.sensitive)
                    .with_context(|| format!("recipe {} has an unsafe path policy", recipe.id))?;
                let declared_paths = paths.allow.iter().chain(&paths.sensitive);
                match file.format {
                    FileFormat::KeyValue
                        if declared_paths
                            .clone()
                            .any(|path| !path.starts_with("/values/")) =>
                    {
                        bail!(
                            "recipe {}: key_value paths must start with /values/",
                            recipe.id
                        );
                    }
                    FileFormat::Ini
                        if declared_paths.clone().any(|path| {
                            !path.starts_with("/global/") && !path.starts_with("/sections/")
                        }) =>
                    {
                        bail!(
                            "recipe {}: ini paths must start with /global/ or /sections/",
                            recipe.id
                        );
                    }
                    _ => {}
                }
            }
            if file
                .checks
                .preflight
                .as_deref()
                .is_some_and(|command| !command.contains("{file}"))
            {
                bail!(
                    "recipe {}: file preflight command must reference the candidate with {{file}}",
                    recipe.id
                );
            }
            if file
                .checks
                .verify
                .as_deref()
                .is_some_and(|command| !command.contains("{path}"))
            {
                bail!(
                    "recipe {}: file verify command must reference the installed file with {{path}}",
                    recipe.id
                );
            }
        }
        if let ConfigEntry::CommandValue(command) = entry {
            if !matches!(
                command.value_type,
                ValueType::Bool | ValueType::Int | ValueType::Float | ValueType::String
            ) {
                bail!(
                    "recipe {}: command_value type must be bool, int, float, or string",
                    recipe.id
                );
            }
            for (operation, invocation) in [("get", &command.get), ("set", &command.set)] {
                if !Path::new(&invocation.executable).is_absolute()
                    || invocation.executable.contains("{value}")
                {
                    bail!(
                        "recipe {}: command_value {operation} executable must be an absolute path without placeholders",
                        recipe.id
                    );
                }
                if invocation
                    .arguments
                    .iter()
                    .any(|argument| argument.as_bytes().contains(&0))
                {
                    bail!(
                        "recipe {}: command_value {operation} arguments cannot contain NUL bytes",
                        recipe.id
                    );
                }
            }
            let placeholders = command
                .set
                .arguments
                .iter()
                .map(|argument| argument.matches("{value}").count())
                .sum::<usize>();
            if placeholders != 1 {
                bail!(
                    "recipe {}: command_value set arguments must contain exactly one {{value}} placeholder",
                    recipe.id
                );
            }
            if command
                .get
                .arguments
                .iter()
                .any(|argument| argument.contains("{value}"))
            {
                bail!(
                    "recipe {}: command_value get arguments cannot contain {{value}}",
                    recipe.id
                );
            }
        }
        if let ConfigEntry::Accessibility(accessibility) = entry {
            if !recipe.requires.iter().any(|value| value == "accessibility") {
                bail!(
                    "recipe {}: accessibility entries require the accessibility permission",
                    recipe.id
                );
            }
            let Some(version) = &recipe.app_version else {
                bail!(
                    "recipe {}: accessibility entries require an exact or major app_version gate",
                    recipe.id
                );
            };
            if version.source != Some(AppVersionSource::BundleShortVersion)
                || version.command.is_some()
            {
                bail!(
                    "recipe {}: accessibility entries require the structured bundle_short_version source",
                    recipe.id
                );
            }
            let app_path = recipe
                .detect
                .as_ref()
                .and_then(|detect| detect.app_path.as_deref())
                .ok_or_else(|| {
                    anyhow!(
                        "recipe {}: accessibility entries require detect.app_path",
                        recipe.id
                    )
                })?;
            let app_path = Path::new(app_path);
            if app_path.parent() != Some(Path::new("/Applications"))
                || app_path.extension().and_then(|value| value.to_str()) != Some("app")
                || recipe
                    .detect
                    .as_ref()
                    .and_then(|detect| detect.command.as_ref())
                    .is_some()
            {
                bail!(
                    "recipe {}: accessibility detection must be a direct /Applications/*.app path with no command",
                    recipe.id
                );
            }
            match accessibility.value_type {
                AccessibilityValueType::Bool => {
                    if !accessibility.allowed_values.is_empty() {
                        bail!(
                            "recipe {}: boolean accessibility entries cannot declare allowed_values",
                            recipe.id
                        );
                    }
                    if !matches!(
                        accessibility.control.role,
                        AccessibilityRole::CheckBox | AccessibilityRole::Switch
                    ) {
                        bail!(
                            "recipe {}: boolean accessibility entries require AXCheckBox or AXSwitch",
                            recipe.id
                        );
                    }
                }
                AccessibilityValueType::Enum => {
                    if accessibility.control.role != AccessibilityRole::PopUpButton {
                        bail!(
                            "recipe {}: enum accessibility entries require AXPopUpButton",
                            recipe.id
                        );
                    }
                    let unique = accessibility
                        .allowed_values
                        .iter()
                        .collect::<std::collections::BTreeSet<_>>();
                    if unique.len() < 2 || unique.len() != accessibility.allowed_values.len() {
                        bail!(
                            "recipe {}: enum accessibility entries require at least two unique allowed_values",
                            recipe.id
                        );
                    }
                }
            }
        }
    }
    if let Some(version) = &recipe.app_version {
        match (&version.command, version.source) {
            (Some(command), None) if !command.trim().is_empty() => {}
            (None, Some(AppVersionSource::BundleShortVersion)) => {}
            (Some(_), Some(_)) => bail!(
                "recipe {}: app_version command and source are mutually exclusive",
                recipe.id
            ),
            _ => bail!(
                "recipe {}: app_version requires a non-empty command or structured source",
                recipe.id
            ),
        }
        if version.supported_majors.is_empty() && version.supported_exact.is_empty() {
            bail!(
                "recipe {}: app_version requires supported_majors or supported_exact",
                recipe.id
            );
        }
        if !version.supported_majors.is_empty() && !version.supported_exact.is_empty() {
            bail!(
                "recipe {}: app_version must choose either supported_majors or supported_exact",
                recipe.id
            );
        }
        if version
            .supported_exact
            .iter()
            .any(|value| value.trim().is_empty() || value.trim() != value)
        {
            bail!(
                "recipe {}: supported_exact versions must be non-empty and trimmed",
                recipe.id
            );
        }
    }
    match recipe.apply.poke {
        Poke::Script if recipe.apply.poke_script.as_deref().unwrap_or("").is_empty() => bail!(
            "recipe {}: poke_script is required when poke is script",
            recipe.id
        ),
        p if p != Poke::Script && recipe.apply.poke_script.is_some() => bail!(
            "recipe {}: poke_script is only valid when poke is script",
            recipe.id
        ),
        _ => {}
    }
    let prefix = format!("profile.{}", recipe.id);
    let ownership = recipe
        .config
        .iter()
        .enumerate()
        .filter_map(|(index, entry)| match entry {
            ConfigEntry::Defaults(value) => Some((
                index,
                format!("{prefix}.{}", value.binds.as_deref().unwrap_or("defaults")),
            )),
            ConfigEntry::File(value) => Some((
                index,
                format!("{prefix}.{}", value.binds.as_deref().unwrap_or("file")),
            )),
            ConfigEntry::Command(value) => Some((index, format!("{prefix}.{}", value.name))),
            ConfigEntry::CommandValue(value) => Some((index, format!("{prefix}.{}", value.name))),
            ConfigEntry::Accessibility(value) => Some((index, format!("{prefix}.{}", value.name))),
            ConfigEntry::GeneratedImport(value) => Some((index, value.source.clone())),
            ConfigEntry::Manual(_) => None,
        })
        .collect::<Vec<_>>();
    for (position, (left_index, left)) in ownership.iter().enumerate() {
        for (right_index, right) in ownership.iter().skip(position + 1) {
            if left == right
                || left.starts_with(&format!("{right}."))
                || right.starts_with(&format!("{left}."))
            {
                bail!(
                    "recipe {} has overlapping profile ownership '{}' and '{}' at config entries {} and {}",
                    recipe.id,
                    left,
                    right,
                    left_index,
                    right_index
                );
            }
        }
    }
    Ok(())
}

pub fn load_values(paths: &[PathBuf]) -> Result<Map<String, Value>> {
    let mut merged = Map::new();
    for path in paths {
        let text = std::fs::read_to_string(path)
            .with_context(|| format!("read values {}", path.display()))?;
        let yaml: serde_yaml::Value = serde_yaml::from_str(&text)
            .with_context(|| format!("parse values {}", path.display()))?;
        let value = serde_json::to_value(yaml)?;
        let object = value
            .as_object()
            .ok_or_else(|| anyhow!("values {} must contain a top-level map", path.display()))?;
        deep_merge_map(&mut merged, object);
    }
    Ok(merged)
}

pub fn deep_merge(target: &mut Value, source: &Value) {
    match (target, source) {
        (Value::Object(a), Value::Object(b)) => deep_merge_map(a, b),
        (a, b) => *a = b.clone(),
    }
}

fn deep_merge_map(target: &mut Map<String, Value>, source: &Map<String, Value>) {
    for (key, value) in source {
        match target.get_mut(key) {
            Some(current) => deep_merge(current, value),
            None => {
                target.insert(key.clone(), value.clone());
            }
        }
    }
}

pub fn validate_value_type(value: &Value, ty: ValueType) -> bool {
    match ty {
        ValueType::Bool => value.is_boolean(),
        ValueType::Int => {
            value.as_i64().is_some() || value.as_u64().and_then(|v| i64::try_from(v).ok()).is_some()
        }
        ValueType::Float => value.as_f64().is_some(),
        ValueType::String | ValueType::Data | ValueType::Date => value.is_string(),
        ValueType::Array => value.is_array(),
        ValueType::Dict => value.is_object(),
    }
}
