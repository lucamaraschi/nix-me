use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};

use anyhow::{bail, Context, Result};
use serde::Serialize;

use crate::engine::recipe_is_installed;
use crate::model::{load_recipe, Artifact, ConfigEntry, Confirm, FileExport, FileFormat, Recipe};
use crate::runner::CommandRunner;

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

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RecipeCatalog {
    pub version: u32,
    pub applications: Vec<RecipeCatalogEntry>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RecipeCatalogEntry {
    pub id: String,
    pub name: String,
    pub bundle_id: String,
    pub installed: bool,
    pub capturable: bool,
    pub capture_kinds: Vec<String>,
    pub exportable_settings: Vec<ExportableSetting>,
    pub managed_paths: Vec<String>,
    pub manual_steps: Vec<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ExportableSetting {
    pub kind: String,
    pub label: String,
    pub source: String,
    pub requires_confirmation: bool,
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

pub fn catalog<R: CommandRunner>(inputs: &[PathBuf], runner: &mut R) -> Result<RecipeCatalog> {
    let recipes = load_registry(inputs)?;
    let applications = recipes
        .into_iter()
        .map(|recipe| {
            let exportable_settings = recipe
                .config
                .iter()
                .flat_map(|entry| match entry {
                    ConfigEntry::Defaults(defaults) => defaults
                        .keys
                        .iter()
                        .map(|(key, schema)| ExportableSetting {
                            kind: "preference".into(),
                            label: schema
                                .ui
                                .clone()
                                .or_else(|| schema.doc.clone())
                                .unwrap_or_else(|| key.clone()),
                            source: format!("{}/{}", defaults.domain, key),
                            requires_confirmation: false,
                        })
                        .collect::<Vec<_>>(),
                    ConfigEntry::File(file)
                        if file.format != FileFormat::Text && file.paths.is_some() =>
                    {
                        vec![ExportableSetting {
                            kind: "file".into(),
                            label: "Allowlisted structured settings file".into(),
                            source: file.path.clone(),
                            requires_confirmation: false,
                        }]
                    }
                    ConfigEntry::File(file) if file.export == FileExport::ReviewedText => {
                        vec![ExportableSetting {
                            kind: "file".into(),
                            label: "Reviewed text settings file".into(),
                            source: file.path.clone(),
                            requires_confirmation: true,
                        }]
                    }
                    ConfigEntry::Command(command) => vec![ExportableSetting {
                        kind: "command".into(),
                        label: "Application-managed list".into(),
                        source: command.name.clone(),
                        requires_confirmation: false,
                    }],
                    ConfigEntry::CommandValue(command) => vec![ExportableSetting {
                        kind: "command_value".into(),
                        label: "Application-managed setting".into(),
                        source: command.name.clone(),
                        requires_confirmation: false,
                    }],
                    ConfigEntry::Accessibility(accessibility) => vec![ExportableSetting {
                        kind: "accessibility".into(),
                        label: accessibility.name.clone(),
                        source: crate::accessibility::target(&recipe.bundle_id, accessibility),
                        requires_confirmation: false,
                    }],
                    ConfigEntry::File(_)
                    | ConfigEntry::GeneratedImport(_)
                    | ConfigEntry::Manual(_) => Vec::new(),
                })
                .collect::<Vec<_>>();
            let managed_paths = recipe
                .config
                .iter()
                .filter_map(|entry| match entry {
                    ConfigEntry::File(file) => Some(file.path.clone()),
                    ConfigEntry::GeneratedImport(entry) => Some(entry.deliver.clone()),
                    ConfigEntry::Defaults(_)
                    | ConfigEntry::Command(_)
                    | ConfigEntry::CommandValue(_)
                    | ConfigEntry::Accessibility(_)
                    | ConfigEntry::Manual(_) => None,
                })
                .collect::<BTreeSet<_>>()
                .into_iter()
                .collect::<Vec<_>>();
            let capture_kinds = recipe
                .config
                .iter()
                .filter_map(|entry| match entry {
                    ConfigEntry::Defaults(_) => Some("defaults"),
                    ConfigEntry::File(file)
                        if file.format != FileFormat::Text && file.paths.is_some() =>
                    {
                        Some("file")
                    }
                    ConfigEntry::File(file) if file.export == FileExport::ReviewedText => {
                        Some("file")
                    }
                    ConfigEntry::Command(_) => Some("command"),
                    ConfigEntry::CommandValue(_) => Some("command_value"),
                    ConfigEntry::Accessibility(_) => Some("accessibility"),
                    ConfigEntry::File(_)
                    | ConfigEntry::GeneratedImport(_)
                    | ConfigEntry::Manual(_) => None,
                })
                .map(str::to_owned)
                .collect::<BTreeSet<_>>()
                .into_iter()
                .collect::<Vec<_>>();
            let manual_steps = recipe
                .config
                .iter()
                .filter_map(|entry| match entry {
                    ConfigEntry::Manual(entry) => Some(entry.step.clone()),
                    _ => None,
                })
                .collect::<Vec<_>>();
            RecipeCatalogEntry {
                installed: recipe_is_installed(&recipe, runner),
                id: recipe.id,
                name: recipe.name,
                bundle_id: recipe.bundle_id,
                capturable: !capture_kinds.is_empty(),
                capture_kinds,
                exportable_settings,
                managed_paths,
                manual_steps,
            }
        })
        .collect();
    Ok(RecipeCatalog {
        version: 1,
        applications,
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
    use crate::runner::ReplayCommandRunner;
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

    #[test]
    fn catalog_reports_only_detected_apps_as_installed() {
        let directory = tempfile::TempDir::new().unwrap();
        fs::write(
            directory.path().join("installed.yaml"),
            "schema_version: 1\nid: installed\nname: Installed\nbundle_id: com.example.Installed\ndetect:\n  command: detect-installed\nconfig:\n  - kind: defaults\n    domain: com.example.Installed\n    keys:\n      enabled: {type: bool}\nverified: null\n",
        )
        .unwrap();
        fs::write(
            directory.path().join("missing.yaml"),
            "schema_version: 1\nid: missing\nname: Missing\nbundle_id: com.example.Missing\ndetect:\n  command: detect-missing\nconfig:\n  - kind: defaults\n    domain: com.example.Missing\n    keys:\n      enabled: {type: bool}\nverified: null\n",
        )
        .unwrap();
        let mut runner = ReplayCommandRunner::default();
        runner
            .outputs
            .insert("detect-installed".into(), Ok(String::new()));
        runner
            .outputs
            .insert("detect-missing".into(), Err("not found".into()));

        let report = catalog(&[directory.path().to_path_buf()], &mut runner).unwrap();

        assert!(report.applications[0].installed);
        assert!(!report.applications[1].installed);
        assert!(report.applications.iter().all(|app| app.capturable));
        assert_eq!(report.applications[0].exportable_settings.len(), 1);
        assert_eq!(
            report.applications[0].exportable_settings[0].source,
            "com.example.Installed/enabled"
        );
    }

    #[test]
    fn catalog_advertises_only_opted_in_text_files_as_exportable() {
        let directory = tempfile::TempDir::new().unwrap();
        fs::write(
            directory.path().join("reviewed.yaml"),
            "schema_version: 1\nid: reviewed\nname: Reviewed\nbundle_id: com.example.Reviewed\nconfig:\n  - kind: file\n    path: ~/.config/reviewed.conf\n    format: text\n    export: reviewed_text\nverified: null\n",
        )
        .unwrap();
        fs::write(
            directory.path().join("closed.yaml"),
            "schema_version: 1\nid: closed\nname: Closed\nbundle_id: com.example.Closed\nconfig:\n  - kind: file\n    path: ~/.config/closed.conf\n    format: text\nverified: null\n",
        )
        .unwrap();
        let mut runner = ReplayCommandRunner::default();

        let report = catalog(&[directory.path().to_path_buf()], &mut runner).unwrap();
        let reviewed = report
            .applications
            .iter()
            .find(|application| application.id == "reviewed")
            .unwrap();
        let closed = report
            .applications
            .iter()
            .find(|application| application.id == "closed")
            .unwrap();

        assert!(reviewed.capturable);
        assert_eq!(reviewed.capture_kinds, ["file"]);
        assert_eq!(reviewed.exportable_settings.len(), 1);
        assert_eq!(
            reviewed.exportable_settings[0].label,
            "Reviewed text settings file"
        );
        assert!(reviewed.exportable_settings[0].requires_confirmation);
        assert!(!closed.capturable);
        assert!(closed.capture_kinds.is_empty());
        assert!(closed.exportable_settings.is_empty());
    }
}
