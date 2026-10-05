use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};

use anyhow::{bail, Context, Result};
use serde::Serialize;

use crate::model::{load_recipe, Artifact, ConfigEntry, Confirm, Recipe};

#[derive(Debug, Serialize)]
pub struct ValidationReport {
    pub version: u32,
    pub valid: bool,
    pub recipes: usize,
    pub ids: Vec<String>,
    pub unverified: Vec<String>,
    pub pipeline_recipes: Vec<String>,
    pub codec_recipes: Vec<String>,
}

#[derive(Debug, Serialize)]
pub struct MetricReport {
    pub version: u32,
    pub denominator: usize,
    pub recipes: usize,
    pub zero_click_apps: usize,
    pub one_click_apps: usize,
    pub full_manual_apps: usize,
    pub uncovered_apps: usize,
    pub zero_click_percent: f64,
    pub entries: EntryCounts,
}

#[derive(Debug, Default, Serialize)]
pub struct EntryCounts {
    pub none: usize,
    pub one_click: usize,
    pub full_manual: usize,
}

pub fn discover_recipe_paths(inputs: &[PathBuf]) -> Result<Vec<PathBuf>> {
    let mut paths = Vec::new();
    for input in inputs {
        discover_recipe_path(input, &mut paths)?;
    }
    paths.sort();
    paths.dedup();
    if paths.is_empty() {
        bail!("no recipe YAML files found");
    }
    Ok(paths)
}

fn discover_recipe_path(input: &Path, paths: &mut Vec<PathBuf>) -> Result<()> {
    if input.is_dir() {
        let mut children = std::fs::read_dir(input)
            .with_context(|| format!("read recipe directory {}", input.display()))?
            .collect::<std::result::Result<Vec<_>, _>>()?;
        children.sort_by_key(|entry| entry.path());
        for entry in children {
            let path = entry.path();
            if path.is_dir() {
                discover_recipe_path(&path, paths)?;
            } else if matches!(
                path.extension().and_then(|extension| extension.to_str()),
                Some("yaml" | "yml")
            ) {
                paths.push(path);
            }
        }
    } else {
        paths.push(input.to_path_buf());
    }
    Ok(())
}

pub fn load_registry(inputs: &[PathBuf]) -> Result<Vec<Recipe>> {
    let paths = discover_recipe_paths(inputs)?;
    let mut ids = BTreeMap::<String, PathBuf>::new();
    let mut recipes = Vec::with_capacity(paths.len());
    for path in paths {
        let recipe = load_recipe(&path)?;
        validate_filename(&path, &recipe.id)?;
        if let Some(previous) = ids.insert(recipe.id.clone(), path.clone()) {
            bail!(
                "duplicate recipe id '{}' in {} and {}",
                recipe.id,
                previous.display(),
                path.display()
            );
        }
        recipes.push(recipe);
    }
    Ok(recipes)
}

fn validate_filename(path: &Path, id: &str) -> Result<()> {
    let stem = path.file_stem().and_then(|value| value.to_str());
    if stem != Some(id) {
        bail!(
            "recipe filename {} must match id '{}': expected {}.yaml",
            path.display(),
            id,
            id
        );
    }
    Ok(())
}

pub fn validate(inputs: &[PathBuf]) -> Result<ValidationReport> {
    let recipes = load_registry(inputs)?;
    let mut unverified = Vec::new();
    let mut pipeline_recipes = BTreeSet::new();
    let mut codec_recipes = BTreeSet::new();
    for recipe in &recipes {
        if recipe.verified.is_none() {
            unverified.push(recipe.id.clone());
        }
        for entry in &recipe.config {
            if let ConfigEntry::GeneratedImport(entry) = entry {
                match &entry.artifact {
                    Artifact::Pipeline { .. } => {
                        pipeline_recipes.insert(recipe.id.clone());
                    }
                    Artifact::Codec { .. } => {
                        codec_recipes.insert(recipe.id.clone());
                    }
                }
            }
        }
    }
    Ok(ValidationReport {
        version: 1,
        valid: true,
        recipes: recipes.len(),
        ids: recipes.iter().map(|recipe| recipe.id.clone()).collect(),
        unverified,
        pipeline_recipes: pipeline_recipes.into_iter().collect(),
        codec_recipes: codec_recipes.into_iter().collect(),
    })
}

pub fn metric(inputs: &[PathBuf], denominator: Option<usize>) -> Result<MetricReport> {
    let recipes = load_registry(inputs)?;
    let denominator = denominator.unwrap_or(recipes.len());
    if denominator < recipes.len() {
        bail!(
            "metric denominator {denominator} cannot be smaller than {} recipes",
            recipes.len()
        );
    }
    let mut entries = EntryCounts::default();
    let mut zero_click_apps = 0;
    let mut one_click_apps = 0;
    let mut full_manual_apps = 0;
    for recipe in &recipes {
        let mut app_level = Confirm::None;
        for entry in &recipe.config {
            let confirm = entry.confirm();
            match confirm {
                Confirm::None => entries.none += 1,
                Confirm::OneClick => entries.one_click += 1,
                Confirm::FullManual => entries.full_manual += 1,
            }
            if severity(confirm) > severity(app_level) {
                app_level = confirm;
            }
        }
        match app_level {
            Confirm::None => zero_click_apps += 1,
            Confirm::OneClick => one_click_apps += 1,
            Confirm::FullManual => full_manual_apps += 1,
        }
    }
    Ok(MetricReport {
        version: 1,
        denominator,
        recipes: recipes.len(),
        zero_click_apps,
        one_click_apps,
        full_manual_apps,
        uncovered_apps: denominator - recipes.len(),
        zero_click_percent: if denominator == 0 {
            0.0
        } else {
            zero_click_apps as f64 * 100.0 / denominator as f64
        },
        entries,
    })
}

fn severity(confirm: Confirm) -> u8 {
    match confirm {
        Confirm::None => 0,
        Confirm::OneClick => 1,
        Confirm::FullManual => 2,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn validates_registry_identity_and_computes_residue_metric() {
        let directory = tempfile::TempDir::new().unwrap();
        let recipe = directory.path().join("example.yaml");
        fs::write(
            &recipe,
            "schema_version: 1\nid: example\nname: Example\nbundle_id: com.example.App\nconfig:\n  - kind: defaults\n    domain: com.example.App\n    keys:\n      enabled: {type: bool}\n  - kind: manual\n    step: Sign in\nverified: null\n",
        )
        .unwrap();
        let validation = validate(&[directory.path().to_path_buf()]).unwrap();
        assert_eq!(validation.ids, ["example"]);
        assert_eq!(validation.unverified, ["example"]);

        let metric = metric(&[directory.path().to_path_buf()], Some(200)).unwrap();
        assert_eq!(metric.recipes, 1);
        assert_eq!(metric.full_manual_apps, 1);
        assert_eq!(metric.uncovered_apps, 199);
        assert_eq!(metric.entries.none, 1);
        assert_eq!(metric.entries.full_manual, 1);
    }

    #[test]
    fn rejects_a_filename_that_does_not_match_the_recipe_id() {
        let directory = tempfile::TempDir::new().unwrap();
        let recipe = directory.path().join("wrong.yaml");
        fs::write(
            &recipe,
            "schema_version: 1\nid: right\nname: Right\nbundle_id: com.example.Right\nconfig:\n  - kind: manual\n    step: Sign in\nverified: null\n",
        )
        .unwrap();
        assert!(validate(&[recipe])
            .unwrap_err()
            .to_string()
            .contains("right.yaml"));
    }

    #[test]
    fn discovers_nested_recipe_directories() {
        let directory = tempfile::TempDir::new().unwrap();
        let nested = directory.path().join("community/editors");
        fs::create_dir_all(&nested).unwrap();
        let recipe = nested.join("nested-app.yml");
        fs::write(
            &recipe,
            "schema_version: 1\nid: nested-app\nname: Nested\nbundle_id: com.example.Nested\nconfig:\n  - kind: manual\n    step: Sign in\nverified: null\n",
        )
        .unwrap();
        let paths = discover_recipe_paths(&[directory.path().to_path_buf()]).unwrap();
        assert_eq!(paths, [recipe]);
    }
}
