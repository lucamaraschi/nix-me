use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};

use anyhow::{bail, Context, Result};
use jsonschema::{Draft, JSONSchema};
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::model::{Confirm, Recipe};
use crate::registry::load_registry;

#[derive(Debug, Deserialize)]
pub struct AppCatalog {
    pub version: u32,
    pub source: CatalogSource,
    pub selection: CatalogSelection,
    pub mechanisms: BTreeMap<String, String>,
    pub applications: Vec<CatalogApplication>,
}

#[derive(Debug, Deserialize)]
pub struct CatalogSource {
    pub provider: String,
    pub analytics_endpoint: String,
    pub metadata_endpoint: String,
    pub window_days: u32,
    pub start_date: String,
    pub end_date: String,
    pub total_cask_events: u64,
}

#[derive(Debug, Deserialize)]
pub struct CatalogSelection {
    pub denominator: usize,
    pub rule: String,
    pub excludes: String,
}

#[derive(Debug, Deserialize)]
pub struct CatalogApplication {
    pub rank: usize,
    pub analytics_rank: usize,
    pub cask: String,
    pub name: String,
    pub description: String,
    pub homepage: String,
    pub installs: u64,
    pub percent: f64,
    pub artifact_kinds: Vec<String>,
    pub signals: CatalogSignals,
    pub behavior: CatalogBehavior,
    pub local_recipe: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct CatalogSignals {
    pub preference_paths: Vec<String>,
    pub config_paths: Vec<String>,
}

#[derive(Debug, Deserialize)]
pub struct CatalogBehavior {
    pub mechanism: String,
    pub confidence: String,
    pub evidence: String,
    pub note: String,
}

#[derive(Debug, Serialize)]
pub struct CatalogValidationReport {
    pub version: u32,
    pub valid: bool,
    pub applications: usize,
    pub analytics_start_date: String,
    pub analytics_end_date: String,
    pub local_recipes: usize,
    pub mechanisms: BTreeMap<String, usize>,
    pub confidence: BTreeMap<String, usize>,
}

#[derive(Debug, Serialize)]
pub struct CatalogMetricReport {
    pub version: u32,
    pub denominator: usize,
    pub behavior_mapped_apps: usize,
    pub local_recipe_apps: usize,
    pub zero_click_apps: usize,
    pub one_click_apps: usize,
    pub full_manual_apps: usize,
    pub uncovered_apps: usize,
    pub zero_click_percent: f64,
    pub mechanisms: BTreeMap<String, usize>,
    pub confidence: BTreeMap<String, usize>,
    pub analytics_start_date: String,
    pub analytics_end_date: String,
}

pub fn load_catalog(path: &Path) -> Result<AppCatalog> {
    let bytes = std::fs::read(path)
        .with_context(|| format!("read application catalog {}", path.display()))?;
    let value: Value = serde_json::from_slice(&bytes)
        .with_context(|| format!("parse application catalog {}", path.display()))?;
    let schema_path = path
        .parent()
        .unwrap_or_else(|| Path::new("."))
        .join("catalog.schema.json");
    let schema: Value = serde_json::from_slice(
        &std::fs::read(&schema_path)
            .with_context(|| format!("read catalog schema {}", schema_path.display()))?,
    )?;
    let compiled = JSONSchema::options()
        .with_draft(Draft::Draft7)
        .compile(&schema)
        .map_err(|error| anyhow::anyhow!("compile catalog schema: {error}"))?;
    if let Err(errors) = compiled.validate(&value) {
        let details = errors
            .map(|error| format!("{}: {}", error.instance_path, error))
            .collect::<Vec<_>>()
            .join("; ");
        bail!("catalog schema validation failed: {details}");
    }
    serde_json::from_value(value)
        .with_context(|| format!("decode application catalog {}", path.display()))
}

pub fn validate(catalog_path: &Path, recipe_inputs: &[PathBuf]) -> Result<CatalogValidationReport> {
    let catalog = load_catalog(catalog_path)?;
    let recipes = load_registry(recipe_inputs)?;
    let (mechanisms, confidence, local_recipes) = validate_loaded(&catalog, &recipes)?;
    Ok(CatalogValidationReport {
        version: 1,
        valid: true,
        applications: catalog.applications.len(),
        analytics_start_date: catalog.source.start_date,
        analytics_end_date: catalog.source.end_date,
        local_recipes,
        mechanisms,
        confidence,
    })
}

pub fn metric(catalog_path: &Path, recipe_inputs: &[PathBuf]) -> Result<CatalogMetricReport> {
    let catalog = load_catalog(catalog_path)?;
    let recipes = load_registry(recipe_inputs)?;
    let (mechanisms, confidence, local_recipe_apps) = validate_loaded(&catalog, &recipes)?;
    let recipes = recipes
        .iter()
        .map(|recipe| (recipe.id.as_str(), recipe))
        .collect::<BTreeMap<_, _>>();
    let mut zero_click_apps = 0;
    let mut one_click_apps = 0;
    let mut full_manual_apps = 0;
    for app in &catalog.applications {
        let Some(recipe_id) = app.local_recipe.as_deref() else {
            continue;
        };
        let recipe = recipes[recipe_id];
        match recipe
            .config
            .iter()
            .map(|entry| entry.confirm())
            .max_by_key(|confirm| severity(*confirm))
            .unwrap_or(Confirm::None)
        {
            Confirm::None => zero_click_apps += 1,
            Confirm::OneClick => one_click_apps += 1,
            Confirm::FullManual => full_manual_apps += 1,
        }
    }
    let denominator = catalog.selection.denominator;
    Ok(CatalogMetricReport {
        version: 1,
        denominator,
        behavior_mapped_apps: catalog.applications.len(),
        local_recipe_apps,
        zero_click_apps,
        one_click_apps,
        full_manual_apps,
        uncovered_apps: denominator - local_recipe_apps,
        zero_click_percent: if denominator == 0 {
            0.0
        } else {
            zero_click_apps as f64 * 100.0 / denominator as f64
        },
        mechanisms,
        confidence,
        analytics_start_date: catalog.source.start_date,
        analytics_end_date: catalog.source.end_date,
    })
}

fn validate_loaded(
    catalog: &AppCatalog,
    recipes: &[Recipe],
) -> Result<(BTreeMap<String, usize>, BTreeMap<String, usize>, usize)> {
    if catalog.version != 1 {
        bail!(
            "unsupported application catalog version {}",
            catalog.version
        );
    }
    if catalog.source.window_days != 365 {
        bail!("application catalog must use the 365-day analytics window");
    }
    if catalog.source.provider.trim().is_empty()
        || !catalog
            .source
            .analytics_endpoint
            .starts_with("https://formulae.brew.sh/")
        || !catalog
            .source
            .metadata_endpoint
            .starts_with("https://formulae.brew.sh/")
        || catalog.source.total_cask_events == 0
    {
        bail!("application catalog source metadata is incomplete");
    }
    if catalog.selection.denominator != catalog.applications.len() {
        bail!(
            "catalog denominator {} does not match {} applications",
            catalog.selection.denominator,
            catalog.applications.len()
        );
    }
    if catalog.selection.denominator != 200 {
        bail!("local application catalog must contain exactly 200 applications");
    }
    if catalog.selection.rule.trim().is_empty()
        || catalog.selection.excludes.trim().is_empty()
        || catalog.mechanisms.is_empty()
    {
        bail!("catalog selection methodology is incomplete");
    }

    let recipe_by_id = recipes
        .iter()
        .map(|recipe| (recipe.id.as_str(), recipe))
        .collect::<BTreeMap<_, _>>();
    let mut seen_casks = BTreeSet::new();
    let mut seen_recipe_ids = BTreeSet::new();
    let mut previous_analytics_rank = 0;
    let mut mechanisms = BTreeMap::<String, usize>::new();
    let mut confidence = BTreeMap::<String, usize>::new();
    let allowed_mechanisms = [
        "defaults_dominant",
        "file_driven",
        "hybrid",
        "cloud_or_opaque",
    ];
    let allowed_confidence = ["high", "medium", "low"];
    let allowed_evidence = ["curated", "homebrew_zap_paths", "homebrew_app_artifact"];

    for (index, app) in catalog.applications.iter().enumerate() {
        if app.rank != index + 1 {
            bail!("catalog rank {} must be {}", app.rank, index + 1);
        }
        if app.analytics_rank <= previous_analytics_rank {
            bail!("analytics ranks must be strictly increasing");
        }
        previous_analytics_rank = app.analytics_rank;
        if !seen_casks.insert(&app.cask) {
            bail!("duplicate catalog cask {}", app.cask);
        }
        if app.name.trim().is_empty()
            || app.description.trim().is_empty()
            || !app.homepage.starts_with("http")
            || app.installs == 0
            || !app.percent.is_finite()
            || app.percent <= 0.0
            || !app.artifact_kinds.iter().any(|kind| kind == "app")
            || app.behavior.note.trim().is_empty()
        {
            bail!(
                "catalog entry {} has incomplete application metadata",
                app.cask
            );
        }
        if !allowed_mechanisms.contains(&app.behavior.mechanism.as_str()) {
            bail!("catalog entry {} has invalid mechanism", app.cask);
        }
        if !allowed_confidence.contains(&app.behavior.confidence.as_str()) {
            bail!("catalog entry {} has invalid confidence", app.cask);
        }
        if !allowed_evidence.contains(&app.behavior.evidence.as_str()) {
            bail!("catalog entry {} has invalid evidence", app.cask);
        }
        *mechanisms
            .entry(app.behavior.mechanism.clone())
            .or_default() += 1;
        *confidence
            .entry(app.behavior.confidence.clone())
            .or_default() += 1;
        for path in app
            .signals
            .preference_paths
            .iter()
            .chain(&app.signals.config_paths)
        {
            if !path.starts_with('~') {
                bail!("catalog signal for {} is not a user path: {path}", app.cask);
            }
        }
        if let Some(recipe_id) = app.local_recipe.as_deref() {
            let recipe = recipe_by_id
                .get(recipe_id)
                .copied()
                .with_context(|| format!("catalog references missing recipe {recipe_id}"))?;
            if !seen_recipe_ids.insert(recipe_id) {
                bail!("local recipe {recipe_id} is mapped to multiple casks");
            }
            let recipe_cask = recipe
                .install
                .as_ref()
                .and_then(|install| install.get("cask"))
                .and_then(|value| value.as_str());
            if recipe_cask != Some(app.cask.as_str()) {
                bail!(
                    "local recipe {recipe_id} installs {:?}, not catalog cask {}",
                    recipe_cask,
                    app.cask
                );
            }
        }
    }
    Ok((mechanisms, confidence, seen_recipe_ids.len()))
}

fn severity(confirm: Confirm) -> u8 {
    match confirm {
        Confirm::None => 0,
        Confirm::OneClick => 1,
        Confirm::FullManual => 2,
    }
}
