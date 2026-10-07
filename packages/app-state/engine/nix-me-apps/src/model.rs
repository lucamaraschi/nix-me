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
    pub merge: Merge,
    #[serde(default = "default_mode")]
    pub mode: String,
    #[serde(default)]
    pub confirm: Confirm,
    pub binds: Option<String>,
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
            Self::GeneratedImport(_) => "generated_import",
            Self::Manual(_) => "manual",
        }
    }
    pub fn bind(&self) -> Option<String> {
        match self {
            Self::Defaults(e) => Some(e.binds.clone().unwrap_or_else(|| "defaults".into())),
            Self::File(e) => Some(e.binds.clone().unwrap_or_else(|| "file".into())),
            Self::Command(e) => Some(e.name.clone()),
            Self::GeneratedImport(e) => Some(e.source.clone()),
            Self::Manual(_) => None,
        }
    }
    pub fn confirm(&self) -> Confirm {
        match self {
            Self::Defaults(e) => e.confirm,
            Self::File(e) => e.confirm,
            Self::Command(e) => e.confirm,
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
            if file.merge == Merge::DeepMerge && file.format == FileFormat::Text {
                bail!("recipe {}: deep_merge is invalid for text files", recipe.id);
            }
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
