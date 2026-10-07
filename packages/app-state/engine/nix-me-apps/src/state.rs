use anyhow::{anyhow, Context, Result};
use fs2::FileExt;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeMap;
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct State {
    pub version: u32,
    pub updated_at: String,
    #[serde(default)]
    pub apps: BTreeMap<String, AppState>,
}
impl Default for State {
    fn default() -> Self {
        Self {
            version: 1,
            updated_at: String::new(),
            apps: BTreeMap::new(),
        }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct AppState {
    #[serde(default)]
    pub entries: BTreeMap<String, EntryState>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub artifact_state: Option<ArtifactState>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct EntryState {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_applied: Option<Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub checksum: Option<String>,
    pub applied_at: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ArtifactState {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub header_b64: Option<String>,
    #[serde(default)]
    pub optional_steps_applied: BTreeMap<String, bool>,
}

pub struct StateGuard {
    pub state: State,
    file: File,
    path: PathBuf,
}

enum StateDecodeError {
    Invalid(serde_json::Error),
    Unsupported(u32),
}

fn decode_state(text: &str) -> std::result::Result<State, StateDecodeError> {
    let state: State = serde_json::from_str(text).map_err(StateDecodeError::Invalid)?;
    if state.version != 1 {
        return Err(StateDecodeError::Unsupported(state.version));
    }
    Ok(state)
}

fn unsupported_version(version: u32) -> anyhow::Error {
    anyhow!("unsupported app-state version {version}; expected version 1")
}

impl StateGuard {
    pub fn acquire(path: &Path, no_wait: bool, now: &str) -> Result<Self> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        let mut file = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .mode(0o600)
            .open(path)?;
        file.set_permissions(fs::Permissions::from_mode(0o600))?;
        match file.try_lock_exclusive() {
            Ok(()) => {}
            Err(error) if no_wait => {
                return Err(error)
                    .context("another nix-me apps apply holds the state lock (--no-wait)");
            }
            Err(_) => {
                eprintln!("another nix-me apps apply holds the state lock; waiting…");
                file.lock_exclusive()
                    .context("wait for nix-me apps state lock")?;
            }
        }
        let mut text = String::new();
        file.read_to_string(&mut text)?;
        let state = if text.trim().is_empty() {
            State::default()
        } else {
            match decode_state(&text) {
                Ok(state) => state,
                Err(StateDecodeError::Unsupported(version)) => {
                    return Err(unsupported_version(version));
                }
                Err(StateDecodeError::Invalid(_)) => {
                    let stamp = now.replace([':', '-'], "");
                    let corrupt = path.with_file_name(format!("apps.json.corrupt-{stamp}"));
                    fs::rename(path, &corrupt).with_context(|| {
                        format!("preserve corrupt state as {}", corrupt.display())
                    })?;
                    file = OpenOptions::new()
                        .read(true)
                        .write(true)
                        .create(true)
                        .mode(0o600)
                        .open(path)?;
                    file.set_permissions(fs::Permissions::from_mode(0o600))?;
                    file.lock_exclusive()?;
                    State::default()
                }
            }
        };
        Ok(Self {
            state,
            file,
            path: path.into(),
        })
    }
    pub fn save(&mut self, now: &str) -> Result<()> {
        self.state.version = 1;
        self.state.updated_at = now.into();
        let bytes = serde_json::to_vec_pretty(&self.state)?;
        self.file.seek(SeekFrom::Start(0))?;
        self.file.set_len(0)?;
        self.file.write_all(&bytes)?;
        self.file.write_all(b"\n")?;
        self.file.sync_all()?;
        Ok(())
    }
    pub fn path(&self) -> &Path {
        &self.path
    }
}

pub fn load_readonly(path: &Path, now: &str) -> Result<State> {
    if !path.exists() {
        return Ok(State::default());
    }
    let text = fs::read_to_string(path)?;
    match decode_state(&text) {
        Ok(v) => Ok(v),
        Err(StateDecodeError::Unsupported(version)) => Err(unsupported_version(version)),
        Err(StateDecodeError::Invalid(_)) => {
            let stamp = now.replace([':', '-'], "");
            let corrupt = path.with_file_name(format!("apps.json.corrupt-{stamp}"));
            fs::rename(path, corrupt)?;
            Ok(State::default())
        }
    }
}

pub fn load_no_mutation(path: &Path) -> Result<(State, Option<String>)> {
    if !path.exists() {
        return Ok((State::default(), None));
    }
    let text = fs::read_to_string(path)?;
    match decode_state(&text) {
        Ok(state) => Ok((state, None)),
        Err(StateDecodeError::Unsupported(version)) => Err(unsupported_version(version)),
        Err(StateDecodeError::Invalid(error)) => Ok((
            State::default(),
            Some(format!(
                "state {} is corrupt ({error}); --no-exec left it unchanged",
                path.display()
            )),
        )),
    }
}

pub fn load_status_no_mutation(path: &Path) -> (State, Option<String>) {
    let text = match fs::read_to_string(path) {
        Ok(text) => text,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return (
                State::default(),
                Some("The persisted app-state status is unavailable".to_owned()),
            );
        }
        Err(_) => {
            return (
                State::default(),
                Some("The persisted app-state status is unavailable".to_owned()),
            );
        }
    };
    match decode_state(&text) {
        Ok(state) => (state, None),
        Err(StateDecodeError::Unsupported(_) | StateDecodeError::Invalid(_)) => (
            State::default(),
            Some("The persisted app-state status is malformed".to_owned()),
        ),
    }
}
