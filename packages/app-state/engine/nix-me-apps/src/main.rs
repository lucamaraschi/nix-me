use std::collections::BTreeSet;
use std::io::{self, IsTerminal, Write};
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use anyhow::{anyhow, Result};
use clap::{Args, Parser, Subcommand};
use nix_me_apps::engine::{command_action_command, poke_command, Engine, Options};
use nix_me_apps::model::{load_recipe, load_values, ConfigEntry, Recipe};
use nix_me_apps::plan::Plan;
use nix_me_apps::runner::{Clock, CommandExecutionError, RealCommandRunner, SystemClock};
use nix_me_apps::state::{load_no_mutation, load_readonly, load_status_no_mutation, StateGuard};
use nix_me_apps::status::{
    apply_message, classify_apply, configured_recipe_count, last_apply_path, load_last_apply,
    record_last_apply, ApplyOutcome, Status,
};

#[derive(Parser)]
#[command(
    name = "nix-me-apps",
    version,
    about = "Declaratively converge macOS application state"
)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Report the read-only application-state status.
    Status(StatusArgs),
    /// Show the convergent plan without changing application state.
    Diff(RunArgs),
    /// Apply a plan, synchronize preference domains, and run required pokes.
    Apply(ApplyArgs),
    /// Capture preference changes or inspect/watch an exported artifact.
    Capture(CaptureArgs),
    /// Validate a recipe registry or compute its zero-click metric.
    Registry(RegistryArgs),
}

#[derive(Args, Clone)]
struct StatusArgs {
    #[arg(long = "recipe", required = true)]
    recipe: Vec<PathBuf>,
    #[arg(long = "values", required = true)]
    values: Vec<PathBuf>,
    #[arg(long, value_delimiter = ',')]
    only: Vec<String>,
    #[arg(long)]
    json: bool,
}

#[derive(Args)]
struct RegistryArgs {
    #[command(subcommand)]
    command: RegistryCommand,
}

#[derive(Subcommand)]
enum RegistryCommand {
    /// Validate schema, semantic invariants, IDs, filenames, and duplicates.
    Validate {
        #[arg(long = "recipe", required = true)]
        recipe: Vec<PathBuf>,
        #[arg(long)]
        json: bool,
    },
    /// Aggregate none/one_click/full_manual residue across all recipes.
    Metric {
        #[arg(long = "recipe", required = true)]
        recipe: Vec<PathBuf>,
        /// Coverage denominator; use 200 for the top-200 registry metric.
        #[arg(long)]
        denominator: Option<usize>,
        #[arg(long)]
        json: bool,
    },
    /// Run every statically linked compiled codec smoke test.
    CodecSmoke {
        #[arg(long)]
        json: bool,
    },
    /// Validate the local Homebrew top-200 application map and recipe links.
    CatalogValidate {
        #[arg(long)]
        catalog: PathBuf,
        #[arg(long = "recipe", required = true)]
        recipe: Vec<PathBuf>,
        #[arg(long)]
        json: bool,
    },
    /// Measure local recipe coverage against the mapped application catalog.
    CatalogMetric {
        #[arg(long)]
        catalog: PathBuf,
        #[arg(long = "recipe", required = true)]
        recipe: Vec<PathBuf>,
        #[arg(long)]
        json: bool,
    },
}

#[derive(Args, Clone)]
struct RunArgs {
    #[arg(long = "recipe", required = true)]
    recipe: Vec<PathBuf>,
    #[arg(long = "values", required = true)]
    values: Vec<PathBuf>,
    #[arg(long, value_delimiter = ',')]
    only: Vec<String>,
    #[arg(long)]
    json: bool,
    #[arg(long)]
    force: bool,
    #[arg(long)]
    skip_manual: bool,
    #[arg(long)]
    skip_missing: bool,
    #[arg(long)]
    require_verified: bool,
    #[arg(long)]
    no_exec: bool,
}

#[derive(Args, Clone)]
struct ApplyArgs {
    #[command(flatten)]
    run: RunArgs,
    #[arg(long)]
    yes: bool,
    #[arg(long)]
    no_wait: bool,
}

#[derive(Args)]
struct CaptureArgs {
    app: Option<String>,
    #[arg(long)]
    domain: Option<String>,
    #[arg(long)]
    watch: bool,
    #[arg(long)]
    sniff: Option<PathBuf>,
    /// Review, then atomically write the latest sniff result or decoded model.
    #[arg(long, requires = "sniff")]
    output: Option<PathBuf>,
    /// Commit output changes to the containing Git repository while watching.
    #[arg(long, requires_all = ["watch", "output"])]
    commit: bool,
    /// Approve capture writes (and --commit) without an interactive prompt.
    #[arg(long, requires = "output", conflicts_with = "dry_run")]
    yes: bool,
    /// Emit the review diff without writing or committing the capture.
    #[arg(long, requires = "output", conflicts_with_all = ["yes", "commit"])]
    dry_run: bool,
    /// Poll interval for --watch, in milliseconds.
    #[arg(long, default_value_t = 750, value_parser = clap::value_parser!(u64).range(100..))]
    poll_ms: u64,
    /// Allow an otherwise-redacted key name or dotted/bracketed path; repeatable.
    #[arg(long = "include-key")]
    include_key: Vec<String>,
    #[arg(long)]
    json: bool,
}

fn main() -> ExitCode {
    match run() {
        Ok(code) => ExitCode::from(code as u8),
        Err((code, error, json)) => {
            if json {
                eprintln!(
                    "{}",
                    serde_json::json!({"version":1,"exit_code":code,"error":error.to_string()})
                );
            } else {
                eprintln!("error: {error:#}");
            }
            ExitCode::from(code as u8)
        }
    }
}

fn run() -> std::result::Result<i32, (i32, anyhow::Error, bool)> {
    let cli = Cli::parse();
    match cli.command {
        Command::Status(args) => {
            let json = args.json;
            run_status(args).map_err(|e| (failure_code(&e, 4), e, json))
        }
        Command::Diff(args) => {
            let json = args.json;
            run_diff(args).map_err(|e| (failure_code(&e, 4), e, json))
        }
        Command::Apply(args) => {
            let json = args.run.json;
            run_apply(args).map_err(|(code, e)| (code, e, json))
        }
        Command::Capture(args) => {
            let json = args.json;
            run_capture(args).map_err(|e| (4, e, json))
        }
        Command::Registry(args) => run_registry(args),
    }
}

fn run_status(args: StatusArgs) -> Result<i32> {
    let (recipes, values) = load_selected_inputs(&args.recipe, &args.values, &args.only)?;
    let clock = SystemClock;
    let path = state_path()?;
    let (mut state, state_warning) = load_status_no_mutation(&path);
    let mut runner = RealCommandRunner {
        no_exec: true,
        ..Default::default()
    };
    let mut prefs = platform_store();
    let mut engine = Engine {
        prefs: &mut prefs,
        runner: &mut runner,
        clock: &clock,
        state: &mut state,
        state_dir: path.parent().unwrap().to_path_buf(),
        options: Options {
            skip_missing: true,
            no_exec: true,
            ..Default::default()
        },
        warnings: vec![],
    };
    if let Some(warning) = state_warning {
        engine.warnings.push(warning);
    }
    let plan = engine.plan(&recipes, &values, "diff")?;
    let mut warnings = engine.warnings.clone();
    drop(engine);
    let (last_apply, last_apply_warning) = load_last_apply(&last_apply_path(&path));
    if let Some(warning) = last_apply_warning {
        warnings.push(warning);
    }
    let status = Status::from_plan(&recipes, &values, &plan, last_apply, warnings);
    emit_status(&status, args.json)?;
    Ok(0)
}

fn run_registry(args: RegistryArgs) -> std::result::Result<i32, (i32, anyhow::Error, bool)> {
    match args.command {
        RegistryCommand::Validate { recipe, json } => {
            let report =
                nix_me_apps::registry::validate(&recipe).map_err(|error| (4, error, json))?;
            emit_registry(&report, json).map_err(|error| (5, error, json))?;
            Ok(0)
        }
        RegistryCommand::Metric {
            recipe,
            denominator,
            json,
        } => {
            let report = nix_me_apps::registry::metric(&recipe, denominator)
                .map_err(|error| (4, error, json))?;
            emit_registry(&report, json).map_err(|error| (5, error, json))?;
            Ok(0)
        }
        RegistryCommand::CodecSmoke { json } => {
            let registry = nix_me_codec::builtin_registry();
            registry.smoke_all().map_err(|error| (5, error, json))?;
            let report = serde_json::json!({"version":1,"status":"ok","codecs":registry.len()});
            emit_registry(&report, json).map_err(|error| (5, error, json))?;
            Ok(0)
        }
        RegistryCommand::CatalogValidate {
            catalog,
            recipe,
            json,
        } => {
            let report = nix_me_apps::catalog::validate(&catalog, &recipe)
                .map_err(|error| (4, error, json))?;
            emit_registry(&report, json).map_err(|error| (5, error, json))?;
            Ok(0)
        }
        RegistryCommand::CatalogMetric {
            catalog,
            recipe,
            json,
        } => {
            let report = nix_me_apps::catalog::metric(&catalog, &recipe)
                .map_err(|error| (4, error, json))?;
            emit_registry(&report, json).map_err(|error| (5, error, json))?;
            Ok(0)
        }
    }
}

fn emit_registry<T: serde::Serialize>(value: &T, json: bool) -> Result<()> {
    if json {
        println!("{}", serde_json::to_string_pretty(value)?);
    } else {
        println!("{}", serde_yaml::to_string(value)?);
    }
    Ok(())
}

fn emit_status(status: &Status, json: bool) -> Result<()> {
    if json {
        println!("{}", serde_json::to_string_pretty(status)?);
    } else {
        println!("{}", serde_yaml::to_string(status)?);
    }
    Ok(())
}

fn run_diff(args: RunArgs) -> Result<i32> {
    let (recipes, values) = load_inputs(&args)?;
    let clock = SystemClock;
    let path = state_path()?;
    let (mut state, state_warning) = if args.no_exec {
        load_no_mutation(&path)?
    } else {
        (load_readonly(&path, &clock.now())?, None)
    };
    let mut runner = RealCommandRunner {
        no_exec: args.no_exec,
        ..Default::default()
    };
    let mut prefs = platform_store();
    let mut engine = Engine {
        prefs: &mut prefs,
        runner: &mut runner,
        clock: &clock,
        state: &mut state,
        state_dir: path.parent().unwrap().to_path_buf(),
        options: options(&args),
        warnings: vec![],
    };
    if let Some(warning) = state_warning {
        engine.warnings.push(warning);
    }
    let plan = engine.plan(&recipes, &values, "diff")?;
    let warnings = engine.warnings.clone();
    drop(engine);
    let commands = audit_commands(&recipes, &plan, &runner.recorded)?;
    emit(&plan, args.json, &warnings, &commands, args.no_exec)?;
    Ok(plan.exit_code)
}

fn run_apply(args: ApplyArgs) -> std::result::Result<i32, (i32, anyhow::Error)> {
    let clock = SystemClock;
    let inputs = load_inputs(&args.run);
    let (recipes, values) = match inputs {
        Ok(inputs) => inputs,
        Err(error) if args.run.no_exec => return Err((4, error)),
        Err(error) => {
            if let Ok(path) = state_path() {
                return Err(record_failed_apply(&path, &clock, 4, error));
            }
            return Err((4, error));
        }
    };
    let path = state_path().map_err(|e| (5, e))?;
    if args.run.no_exec {
        let (mut state, state_warning) = load_no_mutation(&path).map_err(|e| (5, e))?;
        let mut runner = RealCommandRunner {
            no_exec: true,
            ..Default::default()
        };
        let mut prefs = platform_store();
        let mut engine = Engine {
            prefs: &mut prefs,
            runner: &mut runner,
            clock: &clock,
            state: &mut state,
            state_dir: path.parent().unwrap().to_path_buf(),
            options: options(&args.run),
            warnings: vec![],
        };
        if let Some(warning) = state_warning {
            engine.warnings.push(warning);
        }
        let plan = engine
            .plan(&recipes, &values, "apply")
            .map_err(|e| (failure_code(&e, 4), e))?;
        let warnings = engine.warnings.clone();
        drop(engine);
        let commands = audit_commands(&recipes, &plan, &runner.recorded).map_err(|e| (4, e))?;
        emit(&plan, args.run.json, &warnings, &commands, true).map_err(|e| (5, e))?;
        return Ok(plan.exit_code);
    }
    let mut guard = StateGuard::acquire(&path, args.no_wait, &clock.now())
        .map_err(|error| record_failed_apply(&path, &clock, 5, error))?;
    let mut runner = RealCommandRunner {
        no_exec: args.run.no_exec,
        ..Default::default()
    };
    let mut prefs = platform_store();
    let mut engine = Engine {
        prefs: &mut prefs,
        runner: &mut runner,
        clock: &clock,
        state: &mut guard.state,
        state_dir: path.parent().unwrap().to_path_buf(),
        options: options(&args.run),
        warnings: vec![],
    };
    let plan = engine.plan(&recipes, &values, "apply").map_err(|error| {
        let code = failure_code(&error, 4);
        record_failed_apply(&path, &clock, code, error)
    })?;
    if plan.has_actions() {
        let unsafe_restart = recipes.iter().any(|r| {
            r.apply.unsafe_to_kill
                && plan
                    .apps
                    .iter()
                    .any(|a| a.id == r.id && a.entries.iter().any(|e| !e.actions.is_empty()))
        });
        if !args.yes || unsafe_restart {
            if !args.run.json {
                emit(&plan, false, &engine.warnings, &[], false)
                    .map_err(|error| record_failed_apply(&path, &clock, 5, error))?;
            }
            let confirmed = confirm(if unsafe_restart {
                "An app may have unsaved work. Apply and restart it?"
            } else {
                "Apply this plan?"
            })
            .map_err(|error| record_failed_apply(&path, &clock, 5, error))?;
            if !confirmed {
                if args.run.json {
                    emit(&plan, true, &engine.warnings, &[], false)
                        .map_err(|error| record_failed_apply(&path, &clock, 5, error))?;
                }
                record_last_apply(
                    &path,
                    ApplyOutcome::Declined,
                    clock.now(),
                    Some("Apply declined by user".to_owned()),
                )
                .map_err(|error| (5, error))?;
                return Ok(plan.exit_code);
            }
        }
    }
    let plan = engine.apply(&recipes, &values, plan);
    let warnings = engine.warnings.clone();
    drop(engine);
    if let Err(error) = guard.save(&clock.now()) {
        let has_succeeded = plan
            .apps
            .iter()
            .flat_map(|app| &app.entries)
            .flat_map(|entry| &entry.actions)
            .any(|action| action.result.as_deref() == Some("ok"));
        let outcome = if has_succeeded {
            ApplyOutcome::Partial
        } else {
            ApplyOutcome::Failed
        };
        let message = format!(
            "Apply {}: app-state persistence failed: {error}",
            if has_succeeded {
                "completed partially"
            } else {
                "failed"
            }
        );
        let status_result = record_last_apply(&path, outcome, clock.now(), Some(message));
        return Err(match status_result {
            Ok(()) => (5, error),
            Err(status_error) => (
                5,
                anyhow!(
                    "{error:#}; recording the partial apply status also failed: {status_error:#}"
                ),
            ),
        });
    }
    let configured = configured_recipe_count(&recipes, &values);
    record_last_apply(
        &path,
        classify_apply(&plan),
        clock.now(),
        Some(apply_message(&plan, configured)),
    )
    .map_err(|error| (5, error))?;
    emit(&plan, args.run.json, &warnings, &runner.recorded, false).map_err(|e| (5, e))?;
    Ok(plan.exit_code)
}

fn record_failed_apply<C: Clock>(
    state_path: &Path,
    clock: &C,
    code: i32,
    error: anyhow::Error,
) -> (i32, anyhow::Error) {
    let status_result = record_last_apply(
        state_path,
        ApplyOutcome::Failed,
        clock.now(),
        Some(format!("Apply failed: {error:#}")),
    );
    match status_result {
        Ok(()) => (code, error),
        Err(status_error) => (
            code,
            anyhow!("{error:#}; recording the failed apply status also failed: {status_error:#}"),
        ),
    }
}

fn run_capture(args: CaptureArgs) -> Result<i32> {
    let include = args.include_key.into_iter().collect::<BTreeSet<_>>();
    let review_mode = if args.dry_run {
        nix_me_apps::capture::ReviewMode::PreviewOnly
    } else if args.yes {
        nix_me_apps::capture::ReviewMode::AssumeYes
    } else {
        nix_me_apps::capture::ReviewMode::Prompt
    };
    if let Some(path) = args.sniff {
        if args.watch {
            return nix_me_apps::capture::watch_artifact(
                &path,
                args.output.as_deref(),
                args.commit,
                review_mode,
                &include,
                args.poll_ms,
                args.json,
            );
        }
        eprintln!(
            "Capture target: artifact={}; output={}",
            path.display(),
            args.output
                .as_ref()
                .map(|output| output.display().to_string())
                .unwrap_or_else(|| "<stdout-only>".into())
        );
        let output = nix_me_apps::capture::sniff_with_allowlist(&path, &include)?;
        if let Some(destination) = &args.output {
            nix_me_apps::capture::review_sniff_output(
                &path,
                destination,
                &output,
                review_mode,
                false,
            )?;
        }
        if args.json {
            println!("{}", serde_json::to_string_pretty(&output)?);
        } else {
            println!("{}", serde_yaml::to_string(&output)?);
        }
        return Ok(0);
    }

    let output = {
        let app = args
            .app
            .ok_or_else(|| anyhow!("capture requires <app> or --sniff <file>"))?;
        if !io::stdin().is_terminal() {
            return Err(anyhow!(
                "guided capture requires an interactive terminal; use --sniff with --dry-run or --yes for automation"
            ));
        }
        let domain = match args.domain {
            Some(domain) => domain,
            None => nix_me_apps::capture::resolve_bundle_id(&app)?,
        };
        nix_me_apps::capture::interactive_defaults_capture(
            &app,
            &domain,
            &include,
            args.watch,
            args.poll_ms,
        )?
    };
    if args.json {
        println!("{}", serde_json::to_string_pretty(&output)?);
    } else {
        println!("{}", serde_yaml::to_string(&output)?);
    }
    Ok(0)
}

fn load_inputs(
    args: &RunArgs,
) -> Result<(Vec<Recipe>, serde_json::Map<String, serde_json::Value>)> {
    load_selected_inputs(&args.recipe, &args.values, &args.only)
}

fn load_selected_inputs(
    recipe_paths: &[PathBuf],
    value_paths: &[PathBuf],
    only_ids: &[String],
) -> Result<(Vec<Recipe>, serde_json::Map<String, serde_json::Value>)> {
    let only = only_ids.iter().cloned().collect::<BTreeSet<_>>();
    let paths = nix_me_apps::registry::discover_recipe_paths(recipe_paths)?;
    let all_recipes = paths
        .iter()
        .map(|path| load_recipe(path))
        .collect::<Result<Vec<_>>>()?;
    let known = all_recipes
        .iter()
        .map(|recipe| recipe.id.clone())
        .collect::<BTreeSet<_>>();
    if known.len() != all_recipes.len() {
        return Err(anyhow!("duplicate recipe ids in --recipe inputs"));
    }
    let unknown = only.difference(&known).cloned().collect::<Vec<_>>();
    if !unknown.is_empty() {
        return Err(anyhow!(
            "--only contains unknown recipe id(s): {}",
            unknown.join(", ")
        ));
    }
    let recipes = all_recipes
        .into_iter()
        .filter(|r| only.is_empty() || only.contains(&r.id))
        .collect();
    Ok((recipes, load_values(value_paths)?))
}
fn options(args: &RunArgs) -> Options {
    Options {
        force: args.force,
        skip_manual: args.skip_manual,
        skip_missing: args.skip_missing,
        require_verified: args.require_verified,
        no_exec: args.no_exec,
    }
}
fn state_path() -> Result<PathBuf> {
    if let Some(path) = std::env::var_os("NIX_ME_STATE_DIR") {
        return Ok(PathBuf::from(path).join("apps.json"));
    }
    if let Some(path) = std::env::var_os("XDG_STATE_HOME") {
        return Ok(PathBuf::from(path).join("nix-me/apps.json"));
    }
    Ok(
        PathBuf::from(std::env::var_os("HOME").ok_or_else(|| anyhow!("HOME is not set"))?)
            .join(".local/state/nix-me/apps.json"),
    )
}
fn confirm(prompt: &str) -> Result<bool> {
    eprint!("{prompt} [y/N] ");
    io::stderr().flush()?;
    let mut answer = String::new();
    io::stdin().read_line(&mut answer)?;
    Ok(matches!(
        answer.trim().to_ascii_lowercase().as_str(),
        "y" | "yes"
    ))
}
fn emit(
    plan: &Plan,
    json: bool,
    warnings: &[String],
    commands: &[String],
    audit: bool,
) -> Result<()> {
    if json {
        println!("{}", serde_json::to_string_pretty(plan)?);
        if audit {
            eprintln!("Commands (not executed):");
            for command in commands {
                eprintln!("  {command}");
            }
        }
    } else {
        for warning in warnings {
            eprintln!("warning: {warning}");
        }
        for app in &plan.apps {
            println!("{}:", app.id);
            for entry in &app.entries {
                for action in &entry.actions {
                    println!(
                        "  {} {}: {} -> {}{}",
                        match action.op.as_str() {
                            "del" => "-",
                            "write" | "add" | "replace_file" | "merge_file" | "materialize"
                            | "deliver" => "+",
                            _ => "~",
                        },
                        action.target,
                        action
                            .current
                            .as_ref()
                            .map(value_text)
                            .unwrap_or_else(|| "<absent>".into()),
                        action
                            .desired
                            .as_ref()
                            .map(value_text)
                            .unwrap_or_else(|| "<absent>".into()),
                        action
                            .result
                            .as_ref()
                            .map(|r| format!(" [{r}]"))
                            .unwrap_or_default()
                    );
                }
                for drift in &entry.drift {
                    println!("  ! {} ({}) {}", drift.target, drift.reason, drift.detail);
                }
            }
        }
        if !plan.checklist.is_empty() {
            println!("Checklist:");
            for item in &plan.checklist {
                if !item.satisfied {
                    println!("  [ ] {}: {}", item.app, item.step);
                }
            }
        }
        println!("Summary: {} write(s), {} add(s), {} delete(s), {} file(s), {} artifact(s), {} drift, {} manual",plan.summary.writes,plan.summary.adds,plan.summary.dels,plan.summary.files,plan.summary.materialize,plan.summary.drift,plan.summary.manual);
        if audit {
            println!("Commands (not executed):");
            for command in commands {
                println!("  {command}");
            }
        }
    }
    Ok(())
}

fn audit_commands(recipes: &[Recipe], plan: &Plan, recorded: &[String]) -> Result<Vec<String>> {
    let mut commands = Vec::new();
    for command in recorded {
        push_unique(&mut commands, command.clone());
    }
    for app in &plan.apps {
        let Some(recipe) = recipes.iter().find(|recipe| recipe.id == app.id) else {
            continue;
        };
        for (index, entry_plan) in app.entries.iter().enumerate() {
            let Some(entry) = recipe.config.get(index) else {
                continue;
            };
            match entry {
                ConfigEntry::Command(command) => {
                    for action in &entry_plan.actions {
                        push_unique(&mut commands, command_action_command(command, action)?);
                    }
                }
                ConfigEntry::GeneratedImport(_) => {
                    for action in &entry_plan.actions {
                        if action.op == "deliver" {
                            push_unique(&mut commands, action.target.clone());
                        }
                    }
                }
                _ => {}
            }
        }
        if app.entries.iter().any(|entry| !entry.actions.is_empty()) {
            if let Some(command) = poke_command(recipe) {
                push_unique(&mut commands, command);
            }
        }
    }
    Ok(commands)
}
fn push_unique(commands: &mut Vec<String>, command: String) {
    if !commands.contains(&command) {
        commands.push(command);
    }
}
fn failure_code(error: &anyhow::Error, default: i32) -> i32 {
    if error.downcast_ref::<CommandExecutionError>().is_some() {
        5
    } else {
        default
    }
}
fn value_text(value: &serde_json::Value) -> String {
    match value {
        serde_json::Value::String(s) => format!("{s:?}"),
        other => other.to_string(),
    }
}

#[cfg(target_os = "macos")]
fn platform_store() -> nix_me_apps::prefs::CfPrefStore {
    nix_me_apps::prefs::CfPrefStore
}
#[cfg(not(target_os = "macos"))]
fn platform_store() -> nix_me_apps::prefs::DefaultsCliStore {
    nix_me_apps::prefs::DefaultsCliStore
}
