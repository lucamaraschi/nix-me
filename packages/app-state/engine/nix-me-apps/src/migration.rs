use std::collections::BTreeMap;
use std::error::Error;
use std::fmt;
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Write};
use std::os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use anyhow::{anyhow, Context, Result};
use fs2::FileExt;
use serde::Serialize;
use serde_json::{Map, Value};

use crate::model::decode_recipe_value;
use crate::plan::Plan;
use crate::state::State;

const SYNTHETIC_MARKER: &str = "_nix_me_migration_fixture";
const SYNTHETIC_SHAPE: &str = "synthetic-v2";
static UNIQUE_ID: AtomicU64 = AtomicU64::new(0);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum DocumentKind {
    Recipe,
    Plan,
    State,
}

impl DocumentKind {
    fn version_field(self) -> &'static str {
        match self {
            Self::Recipe => "schema_version",
            Self::Plan | Self::State => "version",
        }
    }

    fn format(self) -> &'static str {
        match self {
            Self::Recipe => "YAML",
            Self::Plan | Self::State => "JSON",
        }
    }
}

impl fmt::Display for DocumentKind {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(match self {
            Self::Recipe => "recipe",
            Self::Plan => "plan",
            Self::State => "state",
        })
    }
}

#[derive(Debug, Clone)]
pub struct MigrationRequest {
    pub kind: DocumentKind,
    pub input: PathBuf,
    pub source_version: u32,
    pub target_version: u32,
}

#[derive(Debug, Serialize)]
pub struct MigrationReport {
    pub operation: String,
    pub status: String,
    pub document_kind: DocumentKind,
    pub input_path: PathBuf,
    pub source_version: u32,
    pub target_version: u32,
    pub changed: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub backup_path: Option<PathBuf>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rollback_path: Option<PathBuf>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub canonical_output: Option<String>,
}

impl MigrationReport {
    pub fn summary(&self) -> String {
        match &self.backup_path {
            Some(backup) => format!(
                "applied {} migration {} -> {} to {}; backup={}",
                self.document_kind,
                self.source_version,
                self.target_version,
                self.input_path.display(),
                backup.display()
            ),
            None => format!(
                "dry-run {} migration {} -> {} for {}; canonical {} follows\n",
                self.document_kind,
                self.source_version,
                self.target_version,
                self.input_path.display(),
                self.document_kind.format()
            ),
        }
    }
}

#[derive(Debug)]
pub enum MigrationError {
    Preflight { path: PathBuf, reason: String },
    Apply(Box<MigrationApplyFailure>),
}

#[derive(Debug)]
pub struct MigrationApplyFailure {
    pub path: PathBuf,
    pub backup_path: Option<PathBuf>,
    pub rollback_path: Option<PathBuf>,
    pub rollback_succeeded: bool,
    pub reason: String,
    pub rollback_error: Option<String>,
}

impl MigrationError {
    pub fn is_preflight(&self) -> bool {
        matches!(self, Self::Preflight { .. })
    }

    pub fn json_report(&self, exit_code: i32) -> Value {
        match self {
            Self::Preflight { path, reason } => serde_json::json!({
                "version": 1,
                "exit_code": exit_code,
                "status": "failed",
                "input_path": path,
                "backup_path": null,
                "rollback_path": null,
                "rollback_succeeded": null,
                "reason": reason,
                "error": self.to_string()
            }),
            Self::Apply(failure) => serde_json::json!({
                "version": 1,
                "exit_code": exit_code,
                "status": "failed",
                "input_path": failure.path,
                "backup_path": failure.backup_path,
                "rollback_path": failure.rollback_path,
                "rollback_succeeded": failure.rollback_succeeded,
                "reason": failure.reason,
                "rollback_error": failure.rollback_error,
                "error": self.to_string()
            }),
        }
    }
}

impl fmt::Display for MigrationError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Preflight { path, reason } => write!(
                formatter,
                "migration preflight failed for {}: {}; source was not mutated",
                path.display(),
                reason
            ),
            Self::Apply(failure) => {
                write!(
                    formatter,
                    "migration apply failed for {}: {}",
                    failure.path.display(),
                    failure.reason
                )?;
                if let Some(backup) = &failure.backup_path {
                    write!(formatter, "; backup={}", backup.display())?;
                }
                if let Some(rollback) = &failure.rollback_path {
                    write!(
                        formatter,
                        "; rollback={} ({})",
                        rollback.display(),
                        if failure.rollback_succeeded {
                            "restored"
                        } else {
                            "failed"
                        }
                    )?;
                }
                if let Some(error) = &failure.rollback_error {
                    write!(formatter, "; rollback reason={error}")?;
                }
                Ok(())
            }
        }
    }
}

impl Error for MigrationError {}

struct PreparedMigration {
    source: Vec<u8>,
    canonical: Vec<u8>,
}

pub fn inspect(request: &MigrationRequest) -> std::result::Result<MigrationReport, MigrationError> {
    let source = fs::read(&request.input).map_err(|error| preflight(request, error))?;
    let prepared = prepare(request, source)?;
    Ok(MigrationReport {
        operation: "dry_run".to_owned(),
        status: "ready".to_owned(),
        document_kind: request.kind,
        input_path: request.input.clone(),
        source_version: request.source_version,
        target_version: request.target_version,
        changed: prepared.source != prepared.canonical,
        backup_path: None,
        rollback_path: None,
        canonical_output: Some(String::from_utf8(prepared.canonical).expect("serializer is UTF-8")),
    })
}

pub fn apply(request: &MigrationRequest) -> std::result::Result<MigrationReport, MigrationError> {
    apply_with_injector(request, &NoFailure)
}

fn prepare(
    request: &MigrationRequest,
    source: Vec<u8>,
) -> std::result::Result<PreparedMigration, MigrationError> {
    let value = parse_document(request.kind, &source).map_err(|error| preflight(request, error))?;
    let actual =
        document_version(request.kind, &value).map_err(|error| preflight(request, error))?;
    if actual != request.source_version {
        return Err(preflight(
            request,
            anyhow!(
                "declared source version {} does not match document version {}; use --from {}",
                request.source_version,
                actual,
                actual
            ),
        ));
    }
    ensure_supported_transition(request).map_err(|error| preflight(request, error))?;
    validate_document(request.kind, request.source_version, &value, &request.input)
        .map_err(|error| preflight(request, error))?;
    let migrated = migrate_value(request, value).map_err(|error| preflight(request, error))?;
    validate_document(
        request.kind,
        request.target_version,
        &migrated,
        &request.input,
    )
    .map_err(|error| preflight(request, error))?;
    let canonical = serialize_canonical(request.kind, migrated)
        .and_then(|bytes| {
            let reparsed = parse_document(request.kind, &bytes)?;
            validate_document(
                request.kind,
                request.target_version,
                &reparsed,
                &request.input,
            )?;
            Ok(bytes)
        })
        .map_err(|error| preflight(request, error))?;
    Ok(PreparedMigration { source, canonical })
}

fn parse_document(kind: DocumentKind, bytes: &[u8]) -> Result<Value> {
    match kind {
        DocumentKind::Recipe => {
            let yaml: serde_yaml::Value =
                serde_yaml::from_slice(bytes).context("parse recipe YAML")?;
            serde_json::to_value(yaml).context("convert recipe YAML to a string-keyed document")
        }
        DocumentKind::Plan | DocumentKind::State => {
            serde_json::from_slice(bytes).with_context(|| format!("parse {kind} JSON"))
        }
    }
}

fn document_version(kind: DocumentKind, value: &Value) -> Result<u32> {
    let object = value
        .as_object()
        .ok_or_else(|| anyhow!("{} document root must be an object", kind))?;
    let field = kind.version_field();
    let version = object
        .get(field)
        .and_then(Value::as_u64)
        .ok_or_else(|| anyhow!("/{field} must be an unsigned integer"))?;
    u32::try_from(version).map_err(|_| anyhow!("/{field} exceeds the supported integer range"))
}

fn ensure_supported_transition(request: &MigrationRequest) -> Result<()> {
    if matches!(
        (request.source_version, request.target_version),
        (1, 2) | (2, 1)
    ) {
        return Ok(());
    }
    Err(anyhow!(
        "unsupported {} migration {} -> {}; only synthetic fixture transitions 1 -> 2 and 2 -> 1 are implemented",
        request.kind,
        request.source_version,
        request.target_version
    ))
}

fn validate_document(kind: DocumentKind, version: u32, value: &Value, path: &Path) -> Result<()> {
    let normalized = match version {
        1 => value.clone(),
        2 => normalize_synthetic_v2(kind, value)?,
        _ => return Err(anyhow!("unsupported {kind} version {version}")),
    };
    match kind {
        DocumentKind::Recipe => {
            decode_recipe_value(normalized, path)?;
        }
        DocumentKind::Plan => {
            let plan: Plan = serde_json::from_value(normalized).context("validate plan shape")?;
            if plan.version != 1 {
                return Err(anyhow!(
                    "normalized plan did not resolve to production version 1"
                ));
            }
        }
        DocumentKind::State => {
            let state: State =
                serde_json::from_value(normalized).context("validate state shape")?;
            if state.version != 1 {
                return Err(anyhow!(
                    "normalized state did not resolve to production version 1"
                ));
            }
        }
    }
    Ok(())
}

fn normalize_synthetic_v2(kind: DocumentKind, value: &Value) -> Result<Value> {
    let mut normalized = value.clone();
    let object = normalized
        .as_object_mut()
        .ok_or_else(|| anyhow!("{} document root must be an object", kind))?;
    let marker = object
        .remove(SYNTHETIC_MARKER)
        .ok_or_else(|| {
            anyhow!(
                "version 2 is not the recognized synthetic fixture shape: /{SYNTHETIC_MARKER} is missing"
            )
        })?;
    let expected = synthetic_marker();
    if marker != expected {
        return Err(anyhow!(
            "version 2 is not the recognized synthetic fixture shape: /{SYNTHETIC_MARKER} must equal {}",
            expected
        ));
    }
    object.insert(kind.version_field().to_owned(), Value::from(1));
    Ok(normalized)
}

fn migrate_value(request: &MigrationRequest, mut value: Value) -> Result<Value> {
    let object = value
        .as_object_mut()
        .ok_or_else(|| anyhow!("{} document root must be an object", request.kind))?;
    match (request.source_version, request.target_version) {
        (1, 2) => {
            if object.contains_key(SYNTHETIC_MARKER) {
                return Err(anyhow!(
                    "reserved path /{SYNTHETIC_MARKER} already exists; refusing to overwrite it"
                ));
            }
            object.insert(
                request.kind.version_field().to_owned(),
                Value::from(request.target_version),
            );
            object.insert(SYNTHETIC_MARKER.to_owned(), synthetic_marker());
        }
        (2, 1) => {
            object.remove(SYNTHETIC_MARKER);
            object.insert(
                request.kind.version_field().to_owned(),
                Value::from(request.target_version),
            );
        }
        _ => unreachable!("transition was checked before migration"),
    }
    Ok(value)
}

fn synthetic_marker() -> Value {
    serde_json::json!({
        "shape": SYNTHETIC_SHAPE,
        "production_supported": false
    })
}

fn serialize_canonical(kind: DocumentKind, mut value: Value) -> Result<Vec<u8>> {
    sort_value(&mut value);
    let mut output = match kind {
        DocumentKind::Recipe => serde_yaml::to_string(&value)?.into_bytes(),
        DocumentKind::Plan | DocumentKind::State => serde_json::to_vec_pretty(&value)?,
    };
    if !output.ends_with(b"\n") {
        output.push(b'\n');
    }
    Ok(output)
}

fn sort_value(value: &mut Value) {
    match value {
        Value::Array(items) => items.iter_mut().for_each(sort_value),
        Value::Object(object) => {
            let old = std::mem::take(object);
            let mut sorted = BTreeMap::new();
            for (key, mut value) in old {
                sort_value(&mut value);
                sorted.insert(key, value);
            }
            *object = sorted.into_iter().collect::<Map<_, _>>();
        }
        _ => {}
    }
}

fn preflight(request: &MigrationRequest, error: impl fmt::Display) -> MigrationError {
    MigrationError::Preflight {
        path: request.input.clone(),
        reason: error.to_string(),
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum FailurePoint {
    AfterBackup,
    BeforeReplace,
    AfterReplace,
}

trait FailureInjector {
    fn check(&self, point: FailurePoint) -> std::io::Result<()>;
}

struct NoFailure;

impl FailureInjector for NoFailure {
    fn check(&self, _point: FailurePoint) -> std::io::Result<()> {
        Ok(())
    }
}

fn apply_with_injector(
    request: &MigrationRequest,
    injector: &dyn FailureInjector,
) -> std::result::Result<MigrationReport, MigrationError> {
    let metadata =
        fs::symlink_metadata(&request.input).map_err(|error| preflight(request, error))?;
    if metadata.file_type().is_symlink() || !metadata.file_type().is_file() {
        return Err(preflight(
            request,
            anyhow!("input must be a regular file and must not be a symbolic link"),
        ));
    }
    let mut source_file = OpenOptions::new()
        .read(true)
        .open(&request.input)
        .map_err(|error| preflight(request, error))?;
    let opened_metadata = source_file
        .metadata()
        .map_err(|error| preflight(request, error))?;
    if metadata.dev() != opened_metadata.dev() || metadata.ino() != opened_metadata.ino() {
        return Err(preflight(
            request,
            anyhow!("input changed while it was being opened; retry the migration"),
        ));
    }
    source_file
        .lock_exclusive()
        .map_err(|error| preflight(request, format!("lock source: {error}")))?;
    let mut source = Vec::new();
    source_file
        .read_to_end(&mut source)
        .map_err(|error| preflight(request, format!("read locked source: {error}")))?;
    let prepared = prepare(request, source)?;
    let original_mode = opened_metadata.permissions().mode() & 0o777;
    let backup_path =
        create_atomic_backup(&request.input, &prepared.source).map_err(|failure| {
            MigrationError::Apply(Box::new(MigrationApplyFailure {
                path: request.input.clone(),
                backup_path: failure.path,
                rollback_path: None,
                rollback_succeeded: true,
                reason: format!(
                    "could not create atomic user-only backup: {:#}; source was not mutated",
                    failure.reason
                ),
                rollback_error: None,
            }))
        })?;

    let result = (|| -> Result<()> {
        injector.check(FailurePoint::AfterBackup)?;
        let temporary = write_temporary(&request.input, &prepared.canonical, original_mode)?;
        if let Err(error) = injector.check(FailurePoint::BeforeReplace) {
            let _ = fs::remove_file(&temporary);
            return Err(error.into());
        }
        if let Err(error) = fs::rename(&temporary, &request.input) {
            let _ = fs::remove_file(&temporary);
            return Err(error).context("atomically replace migration input");
        }
        injector.check(FailurePoint::AfterReplace)?;
        sync_parent(&request.input)?;
        Ok(())
    })();

    if let Err(error) = result {
        return Err(rollback_error(request, &backup_path, original_mode, error));
    }

    Ok(MigrationReport {
        operation: "apply".to_owned(),
        status: "applied".to_owned(),
        document_kind: request.kind,
        input_path: request.input.clone(),
        source_version: request.source_version,
        target_version: request.target_version,
        changed: prepared.source != prepared.canonical,
        backup_path: Some(backup_path),
        rollback_path: None,
        canonical_output: None,
    })
}

struct BackupFailure {
    path: Option<PathBuf>,
    reason: anyhow::Error,
}

fn create_atomic_backup(
    source: &Path,
    bytes: &[u8],
) -> std::result::Result<PathBuf, BackupFailure> {
    for _ in 0..64 {
        let backup = unique_neighbor(source, "backup");
        let temporary = write_temporary(&backup, bytes, 0o600)
            .map_err(|reason| BackupFailure { path: None, reason })?;
        match fs::hard_link(&temporary, &backup) {
            Ok(()) => {
                let _ = fs::remove_file(&temporary);
                sync_parent(source)
                    .context("fsync directory after publishing backup")
                    .map_err(|reason| BackupFailure {
                        path: Some(backup.clone()),
                        reason,
                    })?;
                return Ok(backup);
            }
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {
                let _ = fs::remove_file(&temporary);
            }
            Err(error) => {
                let _ = fs::remove_file(&temporary);
                return Err(BackupFailure {
                    path: None,
                    reason: anyhow::Error::from(error)
                        .context("publish migration backup without replacement"),
                });
            }
        }
    }
    Err(BackupFailure {
        path: None,
        reason: anyhow!("could not allocate a unique same-directory backup path after 64 attempts"),
    })
}

fn write_temporary(destination: &Path, bytes: &[u8], mode: u32) -> Result<PathBuf> {
    let (mut file, temporary) = create_temporary(destination)?;
    let result = (|| -> Result<()> {
        file.write_all(bytes)
            .with_context(|| format!("write temporary file {}", temporary.display()))?;
        file.set_permissions(fs::Permissions::from_mode(mode))
            .with_context(|| format!("set temporary file mode {}", temporary.display()))?;
        file.sync_all()
            .with_context(|| format!("fsync temporary file {}", temporary.display()))?;
        Ok(())
    })();
    if let Err(error) = result {
        let _ = fs::remove_file(&temporary);
        return Err(error);
    }
    Ok(temporary)
}

fn create_temporary(destination: &Path) -> Result<(File, PathBuf)> {
    for _ in 0..64 {
        let temporary = unique_neighbor(destination, "tmp");
        match OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&temporary)
        {
            Ok(file) => return Ok((file, temporary)),
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(error) => {
                return Err(error)
                    .with_context(|| format!("create temporary file {}", temporary.display()))
            }
        }
    }
    Err(anyhow!(
        "could not allocate a unique same-directory temporary path after 64 attempts"
    ))
}

fn rollback_error(
    request: &MigrationRequest,
    backup_path: &Path,
    original_mode: u32,
    reason: anyhow::Error,
) -> MigrationError {
    let rollback = restore_backup(backup_path, &request.input, original_mode);
    MigrationError::Apply(Box::new(MigrationApplyFailure {
        path: request.input.clone(),
        backup_path: Some(backup_path.to_path_buf()),
        rollback_path: Some(request.input.clone()),
        rollback_succeeded: rollback.is_ok(),
        reason: format!("{reason:#}"),
        rollback_error: rollback.err().map(|error| format!("{error:#}")),
    }))
}

fn restore_backup(backup: &Path, destination: &Path, mode: u32) -> Result<()> {
    let bytes = fs::read(backup).context("read migration backup for rollback")?;
    let temporary = write_temporary(destination, &bytes, mode)?;
    if let Err(error) = fs::rename(&temporary, destination) {
        let _ = fs::remove_file(&temporary);
        return Err(error).context("atomically restore migration backup");
    }
    sync_parent(destination).context("fsync directory after rollback")
}

fn sync_parent(path: &Path) -> Result<()> {
    let parent = path
        .parent()
        .ok_or_else(|| anyhow!("{} has no parent directory", path.display()))?;
    File::open(parent)
        .with_context(|| format!("open parent directory {}", parent.display()))?
        .sync_all()
        .with_context(|| format!("fsync parent directory {}", parent.display()))
}

fn unique_neighbor(path: &Path, role: &str) -> PathBuf {
    let sequence = UNIQUE_ID.fetch_add(1, Ordering::Relaxed);
    let name = path
        .file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .into_owned();
    path.with_file_name(format!(
        ".{name}.migration-{role}-{}-{sequence}",
        std::process::id()
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::Deserialize;
    use tempfile::TempDir;

    #[derive(Debug, Deserialize)]
    struct FixtureManifest {
        cases: Vec<FixtureCase>,
    }

    #[derive(Debug, Deserialize)]
    struct FixtureCase {
        kind: String,
        source_version: u32,
        target_version: u32,
        source: String,
        expected: String,
    }

    struct FailAt(FailurePoint);

    impl FailureInjector for FailAt {
        fn check(&self, point: FailurePoint) -> std::io::Result<()> {
            if point == self.0 {
                return Err(std::io::Error::new(
                    std::io::ErrorKind::Interrupted,
                    format!("injected interruption at {point:?}"),
                ));
            }
            Ok(())
        }
    }

    fn fixtures() -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../../migrations/fixtures")
    }

    fn kind(value: &str) -> DocumentKind {
        match value {
            "recipe" => DocumentKind::Recipe,
            "plan" => DocumentKind::Plan,
            "state" => DocumentKind::State,
            _ => panic!("unknown fixture kind {value}"),
        }
    }

    #[test]
    fn fixture_matrix_has_canonical_forward_and_backward_outputs() {
        let root = fixtures();
        let manifest: FixtureManifest =
            serde_json::from_slice(&fs::read(root.join("manifest.json")).unwrap()).unwrap();
        assert_eq!(manifest.cases.len(), 6);
        for case in manifest.cases {
            let request = MigrationRequest {
                kind: kind(&case.kind),
                input: root.join(case.source),
                source_version: case.source_version,
                target_version: case.target_version,
            };
            let report = inspect(&request).unwrap();
            let expected = fs::read_to_string(root.join(case.expected)).unwrap();
            assert_eq!(
                report.canonical_output.as_deref(),
                Some(expected.as_str()),
                "{} {} -> {}",
                case.kind,
                case.source_version,
                case.target_version
            );
        }
    }

    #[test]
    fn dry_run_preserves_input_and_creates_no_backup() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("plan.json");
        let original = fs::read(fixtures().join("plan/v1.json")).unwrap();
        fs::write(&path, &original).unwrap();
        let request = MigrationRequest {
            kind: DocumentKind::Plan,
            input: path.clone(),
            source_version: 1,
            target_version: 2,
        };

        let report = inspect(&request).unwrap();

        assert_eq!(report.operation, "dry_run");
        assert_eq!(fs::read(&path).unwrap(), original);
        assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 1);
    }

    #[test]
    fn apply_creates_user_only_backup_and_preserves_unknown_paths() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("state.json");
        let original = fs::read(fixtures().join("state/v1.json")).unwrap();
        fs::write(&path, &original).unwrap();
        let request = MigrationRequest {
            kind: DocumentKind::State,
            input: path.clone(),
            source_version: 1,
            target_version: 2,
        };

        let report = apply(&request).unwrap();
        let backup = report.backup_path.unwrap();
        let migrated: Value = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();

        assert_eq!(fs::read(&backup).unwrap(), original);
        assert_eq!(
            fs::metadata(backup).unwrap().permissions().mode() & 0o777,
            0o600
        );
        assert_eq!(migrated["extension_data"]["nested"]["keep"], true);
        assert_eq!(
            migrated["apps"]["example"]["future_app_field"],
            "preserve-me"
        );
    }

    #[test]
    fn injected_interruption_before_replace_leaves_prior_state_usable() {
        assert_failed_apply_restores(FailurePoint::BeforeReplace);
    }

    #[test]
    fn injected_failure_after_replace_rolls_back_prior_state_atomically() {
        assert_failed_apply_restores(FailurePoint::AfterReplace);
    }

    fn assert_failed_apply_restores(point: FailurePoint) {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("apps.json");
        let original = fs::read(fixtures().join("state/v1.json")).unwrap();
        fs::write(&path, &original).unwrap();
        let request = MigrationRequest {
            kind: DocumentKind::State,
            input: path.clone(),
            source_version: 1,
            target_version: 2,
        };

        let error = apply_with_injector(&request, &FailAt(point)).unwrap_err();

        assert_eq!(fs::read(&path).unwrap(), original);
        match error {
            MigrationError::Apply(failure) if failure.rollback_succeeded => {
                let backup = failure.backup_path.expect("failure must report backup");
                let rollback = failure.rollback_path.expect("failure must report rollback");
                assert!(backup.exists());
                assert_eq!(rollback, path);
                assert!(failure.reason.contains("injected interruption"));
            }
            other => panic!("unexpected failure report: {other}"),
        }
        let (state, warning) = crate::state::load_no_mutation(&path).unwrap();
        assert_eq!(state.version, 1);
        assert!(warning.is_none());
    }

    #[test]
    fn unsupported_versions_are_rejected_without_mutation_or_backup() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("state.json");
        let original = br#"{"version":9,"updated_at":"future","apps":{}}"#.to_vec();
        fs::write(&path, &original).unwrap();
        let request = MigrationRequest {
            kind: DocumentKind::State,
            input: path.clone(),
            source_version: 9,
            target_version: 10,
        };

        let error = apply(&request).unwrap_err();

        assert!(error.is_preflight());
        assert_eq!(fs::read(path).unwrap(), original);
        assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 1);
    }

    #[test]
    fn unrecognized_v2_and_reserved_marker_collisions_are_actionable() {
        let dir = TempDir::new().unwrap();
        let unrecognized = dir.path().join("plan-v2.json");
        fs::write(
            &unrecognized,
            fs::read(fixtures().join("plan/v1.json")).unwrap(),
        )
        .unwrap();
        let mut value: Value = serde_json::from_slice(&fs::read(&unrecognized).unwrap()).unwrap();
        value["version"] = Value::from(2);
        fs::write(&unrecognized, serde_json::to_vec(&value).unwrap()).unwrap();
        let request = MigrationRequest {
            kind: DocumentKind::Plan,
            input: unrecognized.clone(),
            source_version: 2,
            target_version: 1,
        };
        let before = fs::read(&unrecognized).unwrap();

        let error = apply(&request).unwrap_err().to_string();

        assert!(error.contains("/_nix_me_migration_fixture is missing"));
        assert_eq!(fs::read(unrecognized).unwrap(), before);

        let collision = dir.path().join("plan-v1-collision.json");
        let mut value: Value =
            serde_json::from_slice(&fs::read(fixtures().join("plan/v1.json")).unwrap()).unwrap();
        value[SYNTHETIC_MARKER] = serde_json::json!({"owned_by": "external-tool"});
        fs::write(&collision, serde_json::to_vec(&value).unwrap()).unwrap();
        let request = MigrationRequest {
            kind: DocumentKind::Plan,
            input: collision.clone(),
            source_version: 1,
            target_version: 2,
        };
        let before = fs::read(&collision).unwrap();

        let error = apply(&request).unwrap_err().to_string();

        assert!(error.contains("reserved path /_nix_me_migration_fixture already exists"));
        assert_eq!(fs::read(collision).unwrap(), before);
    }

    #[test]
    fn synthetic_v2_remains_rejected_by_production_loaders() {
        let dir = TempDir::new().unwrap();
        let recipe = dir.path().join("recipe.yaml");
        fs::copy(fixtures().join("recipe/v2.synthetic.yaml"), &recipe).unwrap();
        assert!(crate::model::load_recipe(&recipe).is_err());

        let state = dir.path().join("apps.json");
        fs::copy(fixtures().join("state/v2.synthetic.json"), &state).unwrap();
        fs::set_permissions(&state, fs::Permissions::from_mode(0o600)).unwrap();
        let before = fs::read(&state).unwrap();
        let error = crate::state::StateGuard::acquire(&state, false, "2026-10-05T00:00:00Z")
            .err()
            .expect("synthetic v2 state must remain unsupported");
        assert!(error
            .to_string()
            .contains("unsupported app-state version 2"));
        assert_eq!(fs::read(state).unwrap(), before);
    }
}
