use crate::state::ArtifactState;
#[cfg(not(target_os = "macos"))]
use anyhow::anyhow;
use anyhow::{Context, Result};
use base64::Engine as _;
use regex::Regex;
use serde::Serialize;
use serde_json::Value;
use std::collections::BTreeSet;
use std::fs;
use std::io::{self, IsTerminal, Write};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{Duration, SystemTime};

pub fn sniff(path: &Path) -> Result<Value> {
    sniff_with_allowlist(path, &BTreeSet::new())
}

pub fn sniff_with_allowlist(path: &Path, include: &BTreeSet<String>) -> Result<Value> {
    let mut current =
        fs::read(path).with_context(|| format!("read artifact {}", path.display()))?;
    let (mut offset, mut verdict) = (0usize, "opaque");
    let mut pipeline = Vec::<Value>::new();
    let mut header_b64 = None;
    let mut model = None;
    loop {
        if current.len() > 16
            && (looks_decodable(&current[16..]) || try_vendor_aes(&current[16..]).is_some())
        {
            header_b64 =
                Some(base64::engine::general_purpose::STANDARD.encode(current.get(..16).unwrap()));
            pipeline.push(serde_json::json!({"header":{"bytes":16,"keep":true}}));
            offset = 16;
            current = current.split_off(16);
            continue;
        }
        if current.starts_with(&[0x1f, 0x8b]) {
            pipeline.push(serde_json::json!({"gzip":{}}));
            let mut out = Vec::new();
            use std::io::Read;
            flate2::read::GzDecoder::new(current.as_slice()).read_to_end(&mut out)?;
            current = out;
            continue;
        }
        if current.starts_with(b"PK\x03\x04") {
            pipeline.push(serde_json::json!({"zip":{}}));
            verdict = "container";
            break;
        }
        if current.len() > 262 && &current[257..262] == b"ustar" {
            pipeline.push(serde_json::json!({"tar":{}}));
            verdict = "container";
            break;
        }
        if current.starts_with(b"bplist00") || current.starts_with(b"<?xml") {
            pipeline.push(serde_json::json!({"plist":{"flavor":"auto"}}));
            verdict = "plist";
            if let Ok(parsed) = plist::Value::from_reader(std::io::Cursor::new(&current)) {
                model = Some(crate::prefs::plist_to_json(&parsed));
            }
            break;
        }
        if current.starts_with(b"SQLite format 3\0") {
            pipeline.push(serde_json::json!({"sqlite":{"tables":{}}}));
            verdict = "sqlite_v2";
            break;
        }
        if current.starts_with(b"Salted__") {
            pipeline.push(serde_json::json!({"aes":{"algo":"aes-256-cbc","salted":true,"optional":false,"password":{"default":"12345678","profile_key":"secrets.export_password"}}}));
            if let Ok(decrypted) = crate::pipeline::openssl_aes_bytes(
                false,
                "aes-256-cbc",
                b"12345678",
                true,
                &current,
            ) {
                if looks_decodable(&decrypted) {
                    current = decrypted;
                    continue;
                }
            }
            verdict = "encrypted";
            break;
        }
        if let Some(decrypted) = try_vendor_aes(&current) {
            pipeline.push(serde_json::json!({"aes":{"algo":"aes-256-cbc","optional":true,"password":{"default":"12345678","profile_key":"secrets.export_password"},"salted":false}}));
            current = decrypted;
            continue;
        }
        if let Ok(parsed) = serde_json::from_slice::<Value>(&current) {
            pipeline.push(serde_json::json!({"json":{}}));
            verdict = "json";
            model = Some(parsed);
            break;
        }
        if let Ok(text) = std::str::from_utf8(&current) {
            let compact = text
                .chars()
                .filter(|c| !c.is_whitespace())
                .collect::<String>();
            if compact.len() >= 8 && compact.len() % 4 == 0 {
                if let Ok(decoded) = base64::engine::general_purpose::STANDARD.decode(&compact) {
                    if decoded != current && looks_decodable(&decoded) {
                        pipeline.push(serde_json::json!({"base64":{}}));
                        current = decoded;
                        continue;
                    }
                }
            }
            if let Ok(parsed) = text.parse::<toml::Value>() {
                if parsed.is_table() {
                    pipeline.push(serde_json::json!({"toml":{}}));
                    verdict = "toml";
                    model = Some(serde_json::to_value(parsed)?);
                    break;
                }
            }
            if let Ok(parsed) = serde_yaml::from_str::<serde_yaml::Value>(text) {
                if matches!(
                    parsed,
                    serde_yaml::Value::Mapping(_) | serde_yaml::Value::Sequence(_)
                ) {
                    pipeline.push(serde_json::json!({"yaml":{}}));
                    verdict = "yaml";
                    model = Some(serde_json::to_value(parsed)?);
                    break;
                }
            }
        }
        if shannon_entropy(&current) >= 7.2 {
            verdict = "probably_encrypted";
        }
        break;
    }
    let decoded = model.is_some();
    let redactions = model
        .as_mut()
        .map(|value| redact_secrets(value, include))
        .unwrap_or_default();
    Ok(serde_json::json!({
        "version":1,
        "file":path,
        "offset":offset,
        "header_b64":header_b64,
        "pipeline":pipeline,
        "verdict":verdict,
        "decoded":decoded,
        "model":model,
        "redaction":redaction_metadata(include, &redactions)
    }))
}

fn try_vendor_aes(input: &[u8]) -> Option<Vec<u8>> {
    let output =
        crate::pipeline::openssl_aes_bytes(false, "aes-256-cbc", b"12345678", false, input).ok()?;
    looks_decodable(&output).then_some(output)
}

fn looks_decodable(input: &[u8]) -> bool {
    input.starts_with(&[0x1f, 0x8b])
        || input.starts_with(b"PK\x03\x04")
        || input.starts_with(b"bplist00")
        || input.starts_with(b"<?xml")
        || input.starts_with(b"SQLite format 3\0")
        || serde_json::from_slice::<Value>(input).is_ok()
        || (input.len() > 16 && input[16..].starts_with(&[0x1f, 0x8b]))
}

fn shannon_entropy(input: &[u8]) -> f64 {
    if input.len() < 32 {
        return 0.0;
    }
    let mut counts = [0usize; 256];
    for byte in input {
        counts[*byte as usize] += 1;
    }
    let len = input.len() as f64;
    counts
        .into_iter()
        .filter(|count| *count > 0)
        .map(|count| {
            let probability = count as f64 / len;
            -probability * probability.log2()
        })
        .sum()
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct Redaction {
    pub path: String,
    pub reason: &'static str,
    pub action: &'static str,
}

pub fn redact_secrets(value: &mut Value, include: &BTreeSet<String>) -> Vec<Redaction> {
    let pattern = Regex::new(
        "(?i)(authorization|auth[_-]?token|bearer|cookie|credential|pass(word|phrase)?|secret|session[_-]?(id|key|token)?|token|api[_-]?key|access[_-]?key|private[_-]?key|client[_-]?secret|refresh[_-]?token|webhook[_-]?url)",
    )
    .unwrap();
    let mut redactions = Vec::new();
    redact_walk(value, "", None, include, &pattern, &mut redactions);
    redactions.sort_by(|left, right| {
        left.path
            .cmp(&right.path)
            .then(left.reason.cmp(right.reason))
    });
    redactions
}

fn redact_walk(
    value: &mut Value,
    path: &str,
    key: Option<&str>,
    include: &BTreeSet<String>,
    pattern: &Regex,
    redactions: &mut Vec<Redaction>,
) {
    if is_allowlisted(path, key, include) {
        return;
    }
    match value {
        Value::Object(map) => {
            let mut keys = map.keys().cloned().collect::<Vec<_>>();
            keys.sort();
            for key in keys {
                let child = if path.is_empty() {
                    key.clone()
                } else {
                    format!("{path}.{key}")
                };
                if is_allowlisted(&child, Some(&key), include) {
                    continue;
                }
                let secret_name = pattern.is_match(&key);
                let high_entropy = map
                    .get(&key)
                    .and_then(|v| v.as_str())
                    .map(is_high_entropy)
                    .unwrap_or(false);
                if secret_name || high_entropy {
                    map.remove(&key);
                    redactions.push(Redaction {
                        path: child,
                        reason: if secret_name {
                            "sensitive_key"
                        } else {
                            "high_entropy_string"
                        },
                        action: "removed",
                    });
                } else if let Some(v) = map.get_mut(&key) {
                    redact_walk(v, &child, Some(&key), include, pattern, redactions);
                }
            }
        }
        Value::Array(items) => {
            for (index, item) in items.iter_mut().enumerate() {
                let child = format!("{path}[{index}]");
                if is_allowlisted(&child, None, include) {
                    continue;
                }
                if item.as_str().map(is_high_entropy).unwrap_or(false) {
                    // Preserve positions so the redaction path still identifies the source item.
                    *item = Value::Null;
                    redactions.push(Redaction {
                        path: child,
                        reason: "high_entropy_string",
                        action: "replaced_with_null",
                    });
                } else {
                    redact_walk(item, &child, None, include, pattern, redactions);
                }
            }
        }
        Value::String(text) if is_high_entropy(text) => {
            *value = Value::Null;
            redactions.push(Redaction {
                path: if path.is_empty() {
                    "$".into()
                } else {
                    path.into()
                },
                reason: "high_entropy_string",
                action: "replaced_with_null",
            });
        }
        _ => {}
    }
}

fn is_allowlisted(path: &str, key: Option<&str>, include: &BTreeSet<String>) -> bool {
    include.contains(path) || key.is_some_and(|key| include.contains(key))
}

fn redaction_metadata(include: &BTreeSet<String>, redactions: &[Redaction]) -> Value {
    serde_json::json!({
        "policy":"default_closed",
        "allowlisted_paths":include,
        "count":redactions.len(),
        "items":redactions
    })
}
fn is_high_entropy(value: &str) -> bool {
    if value.len() < 24 {
        return false;
    }
    let mut seen = [false; 256];
    let unique = value
        .bytes()
        .filter(|b| {
            let fresh = !seen[*b as usize];
            seen[*b as usize] = true;
            fresh
        })
        .count();
    unique >= 16 && !value.contains(' ')
}

pub fn interactive_defaults_capture(
    app: &str,
    domain: &str,
    include: &BTreeSet<String>,
    watch: bool,
    poll_ms: u64,
) -> Result<Value> {
    #[cfg(not(target_os = "macos"))]
    {
        let _ = (app, domain, include, watch, poll_ms);
        return Err(anyhow!(
            "interactive defaults capture requires macOS; --sniff works on every platform"
        ));
    }
    #[cfg(target_os = "macos")]
    {
        if !io::stdin().is_terminal() {
            return Err(anyhow::anyhow!(
                "guided capture requires an interactive terminal; use --sniff with --dry-run or --yes for automation"
            ));
        }
        let artifact = format!("defaults:{domain}");
        eprintln!("Capture target: app={app:?}, domain={domain:?}, artifact={artifact:?}");
        eprintln!("Step 1/3 BEFORE: recording the current preference baseline.");
        let before_any = export_domain(domain, false)?;
        let before_current = export_domain(domain, true)?;
        if watch {
            watch_preference_session(app, domain, &before_any, &before_current, poll_ms)?;
        } else {
            eprintln!(
                "Step 2/3 CHANGE: change {app} in its GUI for domain {domain}, then press Enter."
            );
            io::stdin().read_line(&mut String::new())?;
        }
        eprintln!("Step 3/3 AFTER: recording the updated preference state.");
        let after_any = export_domain(domain, false)?;
        let after_current = export_domain(domain, true)?;
        let mut changed = serde_json::Map::new();
        let mut current_host = BTreeSet::new();
        collect_changes(&before_any, &after_any, &mut changed, None);
        collect_changes(
            &before_current,
            &after_current,
            &mut changed,
            Some(&mut current_host),
        );
        let mut values = Value::Object(changed);
        let redactions = redact_secrets(&mut values, include);
        eprint!("UI location for this {app} change (for example, Settings > General): ");
        io::stderr().flush()?;
        let mut ui = String::new();
        io::stdin().read_line(&mut ui)?;
        let id = app
            .to_ascii_lowercase()
            .chars()
            .map(|c| if c.is_ascii_alphanumeric() { c } else { '-' })
            .collect::<String>()
            .trim_matches('-')
            .to_string();
        let keys = values
            .as_object()
            .into_iter()
            .flatten()
            .map(|(key, value)| {
                let mut schema = serde_json::json!({"type":inferred_type(value),"ui":ui.trim()});
                if current_host.contains(key) {
                    schema["host"] = Value::String("current".into());
                }
                (key.clone(), schema)
            })
            .collect::<serde_json::Map<_, _>>();
        let sandboxed = home_dir()
            .map(|home| home.join("Library/Containers").join(domain).exists())
            .unwrap_or(false);
        let app_path = format!("/Applications/{app}.app");
        Ok(
            serde_json::json!({"version":1,"capture":{"mode":"guided","app":app,"domain":domain,"artifact":artifact},"recipe_fragment":{"schema_version":1,"id":id,"name":app,"bundle_id":domain,"detect":{"app_path":app_path},"sandboxed":sandboxed,"requires":if sandboxed{vec!["full_disk_access"]}else{Vec::<&str>::new()},"config":[{"kind":"defaults","domain":domain,"keys":keys,"unknown_keys":"passthrough"}],"apply":{"poke":"restart_app"},"verified":null},"profile_fragment":{(id):values},"redaction":redaction_metadata(include, &redactions)}),
        )
    }
}

#[cfg(target_os = "macos")]
fn watch_preference_session(
    app: &str,
    domain: &str,
    before_any: &Value,
    before_current: &Value,
    poll_ms: u64,
) -> Result<()> {
    use std::sync::mpsc;

    eprintln!(
        "Step 2/3 CHANGE: watching {app} domain {domain}; make GUI changes, then press Enter."
    );
    let (sender, receiver) = mpsc::channel();
    std::thread::spawn(move || {
        let mut line = String::new();
        let result = io::stdin().read_line(&mut line);
        let _ = sender.send(result);
    });
    let mut reported = BTreeSet::new();
    loop {
        match receiver.recv_timeout(Duration::from_millis(poll_ms)) {
            Ok(result) => {
                result?;
                return Ok(());
            }
            Err(mpsc::RecvTimeoutError::Disconnected) => {
                return Err(anyhow::anyhow!("capture input channel closed"));
            }
            Err(mpsc::RecvTimeoutError::Timeout) => {
                let current_any = export_domain(domain, false)?;
                let current_host = export_domain(domain, true)?;
                let mut changed = serde_json::Map::new();
                collect_changes(before_any, &current_any, &mut changed, None);
                collect_changes(before_current, &current_host, &mut changed, None);
                for key in changed.keys() {
                    if reported.insert(key.clone()) {
                        eprintln!("  observed change: {key}");
                    }
                }
            }
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ReviewMode {
    Prompt,
    AssumeYes,
    PreviewOnly,
}

pub fn capture_diff(before: Option<&Value>, after: &Value) -> Value {
    let before = before.map(canonicalize);
    let after = canonicalize(after);
    let mut changes = Vec::new();
    diff_values(before.as_ref(), Some(&after), "$", &mut changes);
    let adds = changes
        .iter()
        .filter(|change| change["op"] == "add")
        .count();
    let removes = changes
        .iter()
        .filter(|change| change["op"] == "remove")
        .count();
    let replaces = changes.len() - adds - removes;
    serde_json::json!({
        "version":1,
        "changes":changes,
        "summary":{"adds":adds,"removes":removes,"replaces":replaces}
    })
}

fn diff_values(
    before: Option<&Value>,
    after: Option<&Value>,
    path: &str,
    changes: &mut Vec<Value>,
) {
    match (before, after) {
        (Some(left), Some(right)) if left == right => {}
        (Some(Value::Object(left)), Some(Value::Object(right))) => {
            let keys = left
                .keys()
                .chain(right.keys())
                .cloned()
                .collect::<BTreeSet<_>>();
            for key in keys {
                let child = format!("{path}/{}", json_pointer_segment(&key));
                diff_values(left.get(&key), right.get(&key), &child, changes);
            }
        }
        (Some(Value::Array(left)), Some(Value::Array(right))) => {
            for index in 0..left.len().max(right.len()) {
                diff_values(
                    left.get(index),
                    right.get(index),
                    &format!("{path}/{index}"),
                    changes,
                );
            }
        }
        (None, Some(Value::Object(right))) if !right.is_empty() => {
            for (key, value) in right {
                let child = format!("{path}/{}", json_pointer_segment(key));
                diff_values(None, Some(value), &child, changes);
            }
        }
        (Some(Value::Object(left)), None) if !left.is_empty() => {
            for (key, value) in left {
                let child = format!("{path}/{}", json_pointer_segment(key));
                diff_values(Some(value), None, &child, changes);
            }
        }
        (None, Some(value)) => changes.push(serde_json::json!({
            "op":"add",
            "path":path,
            "after":canonicalize(value)
        })),
        (Some(value), None) => changes.push(serde_json::json!({
            "op":"remove",
            "path":path,
            "before":canonicalize(value)
        })),
        (Some(left), Some(right)) => changes.push(serde_json::json!({
            "op":"replace",
            "path":path,
            "before":canonicalize(left),
            "after":canonicalize(right)
        })),
        (None, None) => {}
    }
}

fn json_pointer_segment(segment: &str) -> String {
    segment.replace('~', "~0").replace('/', "~1")
}

fn canonicalize(value: &Value) -> Value {
    match value {
        Value::Object(map) => {
            let mut keys = map.keys().collect::<Vec<_>>();
            keys.sort();
            Value::Object(
                keys.into_iter()
                    .map(|key| (key.clone(), canonicalize(&map[key])))
                    .collect(),
            )
        }
        Value::Array(items) => Value::Array(items.iter().map(canonicalize).collect()),
        other => other.clone(),
    }
}

fn captured_output(result: &Value) -> &Value {
    if result["decoded"] == true {
        &result["model"]
    } else {
        result
    }
}

fn review_allowlist(result: &Value) -> BTreeSet<String> {
    result["redaction"]["allowlisted_paths"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .map(ToOwned::to_owned)
        .collect()
}

fn read_existing_output(
    path: &Path,
    include: &BTreeSet<String>,
) -> Result<(Option<Value>, Vec<Redaction>)> {
    match fs::read(path) {
        Ok(bytes) => {
            let mut value: Value = serde_json::from_slice(&bytes)
                .with_context(|| format!("parse existing capture output {}", path.display()))?;
            let redactions = redact_secrets(&mut value, include);
            Ok((Some(value), redactions))
        }
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok((None, Vec::new())),
        Err(error) => Err(error).with_context(|| format!("read capture output {}", path.display())),
    }
}

pub fn review_sniff_output(
    source: &Path,
    output: &Path,
    result: &Value,
    mode: ReviewMode,
    commit: bool,
) -> Result<bool> {
    if commit && mode == ReviewMode::PreviewOnly {
        return Err(anyhow::anyhow!(
            "a preview-only capture cannot be committed"
        ));
    }
    let proposed = canonicalize(captured_output(result));
    let include = review_allowlist(result);
    let (existing, existing_redactions) = read_existing_output(output, &include)?;
    let diff = capture_diff(existing.as_ref(), &proposed);
    let has_changes = diff["changes"]
        .as_array()
        .map(|changes| !changes.is_empty())
        .unwrap_or(false);
    let preview = serde_json::json!({
        "version":1,
        "source_artifact":source,
        "output_artifact":output,
        "redaction":result.get("redaction").cloned().unwrap_or(Value::Null),
        "existing_output_redactions":existing_redactions,
        "diff":diff
    });
    eprintln!(
        "Capture review: source artifact={}, output artifact={}",
        source.display(),
        output.display()
    );
    eprintln!("{}", serde_json::to_string_pretty(&preview)?);
    io::stderr().flush()?;

    if !has_changes {
        eprintln!("No output changes detected; nothing will be written or committed.");
        return Ok(false);
    }
    if mode == ReviewMode::Prompt && !io::stdin().is_terminal() {
        return Err(anyhow::anyhow!(
            "capture output requires explicit consent in non-interactive mode; pass --yes to write or --dry-run to preview"
        ));
    }
    match mode {
        ReviewMode::PreviewOnly => {
            eprintln!("Preview only; nothing was written or committed.");
            return Ok(false);
        }
        ReviewMode::Prompt => {
            let action = if commit { "write and commit" } else { "write" };
            if !confirm(&format!("{action} this capture to {}?", output.display()))? {
                eprintln!("Capture declined; nothing was written or committed.");
                return Ok(false);
            }
        }
        ReviewMode::AssumeYes => {}
    }

    write_capture_output(output, &proposed)?;
    if commit {
        commit_capture(output)?;
    }
    Ok(true)
}

fn confirm(prompt: &str) -> Result<bool> {
    if !io::stdin().is_terminal() {
        return Err(anyhow::anyhow!(
            "refusing to prompt without an interactive terminal"
        ));
    }
    eprint!("{prompt} [y/N] ");
    io::stderr().flush()?;
    let mut answer = String::new();
    io::stdin().read_line(&mut answer)?;
    Ok(matches!(
        answer.trim().to_ascii_lowercase().as_str(),
        "y" | "yes"
    ))
}

fn write_capture_output(path: &Path, output: &Value) -> Result<()> {
    let parent = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    fs::create_dir_all(parent)?;
    let temporary = parent.join(format!(
        ".{}.tmp-{}",
        path.file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("capture"),
        std::process::id()
    ));
    let mut bytes = serde_json::to_vec_pretty(output)?;
    bytes.push(b'\n');
    let mut file = fs::OpenOptions::new()
        .create(true)
        .truncate(true)
        .write(true)
        .mode(0o600)
        .open(&temporary)?;
    file.set_permissions(fs::Permissions::from_mode(0o600))?;
    file.write_all(&bytes)?;
    file.sync_all()?;
    drop(file);
    fs::rename(&temporary, path)?;
    fs::set_permissions(path, fs::Permissions::from_mode(0o600))?;
    Ok(())
}

pub fn watch_artifact(
    source: &Path,
    output: Option<&Path>,
    commit: bool,
    mode: ReviewMode,
    include: &BTreeSet<String>,
    poll_ms: u64,
    json: bool,
) -> Result<i32> {
    if commit && output.is_none() {
        return Err(anyhow::anyhow!("--commit requires --output"));
    }
    eprintln!(
        "Capture target: artifact={}; output={}. Watching for changes; press Ctrl-C to stop.",
        source.display(),
        output
            .map(|path| path.display().to_string())
            .unwrap_or_else(|| "<stdout-only>".into())
    );
    let mut last_modified = None;
    loop {
        let modified = fs::metadata(source)
            .with_context(|| format!("inspect artifact {}", source.display()))?
            .modified()
            .unwrap_or(SystemTime::UNIX_EPOCH);
        if last_modified != Some(modified) {
            let result = sniff_with_allowlist(source, include)?;
            if let Some(path) = output {
                review_sniff_output(source, path, &result, mode, commit)?;
            }
            if json {
                println!("{}", serde_json::to_string(&result)?);
            } else {
                println!("{}", serde_yaml::to_string(&result)?);
            }
            io::stdout().flush()?;
            last_modified = Some(modified);
        }
        std::thread::sleep(Duration::from_millis(poll_ms));
    }
}

fn commit_capture(path: &Path) -> Result<()> {
    let repo = path
        .ancestors()
        .find(|candidate| candidate.join(".git").exists())
        .ok_or_else(|| anyhow::anyhow!("{} is not inside a Git worktree", path.display()))?;
    let relative = path.strip_prefix(repo)?;
    let add = Command::new("git")
        .current_dir(repo)
        .arg("add")
        .arg("--")
        .arg(relative)
        .status()?;
    if !add.success() {
        return Err(anyhow::anyhow!("git add failed for {}", path.display()));
    }
    let changed = Command::new("git")
        .current_dir(repo)
        .args(["diff", "--cached", "--quiet", "--"])
        .arg(relative)
        .status()?;
    if changed.success() {
        return Ok(());
    }
    let commit = Command::new("git")
        .current_dir(repo)
        .args(["commit", "-m"])
        .arg(format!("capture: update {}", relative.display()))
        .args(["--"])
        .arg(relative)
        .status()?;
    if !commit.success() {
        return Err(anyhow::anyhow!("git commit failed for {}", path.display()));
    }
    Ok(())
}
fn collect_changes(
    before: &Value,
    after: &Value,
    changed: &mut serde_json::Map<String, Value>,
    current: Option<&mut BTreeSet<String>>,
) {
    if let (Some(a), Some(b)) = (before.as_object(), after.as_object()) {
        let mut current = current;
        for (k, v) in b {
            if a.get(k) != Some(v) {
                changed.insert(k.clone(), v.clone());
                if let Some(keys) = current.as_deref_mut() {
                    keys.insert(k.clone());
                }
            }
        }
    }
}
fn inferred_type(value: &Value) -> &'static str {
    match value {
        Value::Bool(_) => "bool",
        Value::Number(n) if n.is_i64() || n.is_u64() => "int",
        Value::Number(_) => "float",
        Value::String(_) => "string",
        Value::Array(_) => "array",
        Value::Object(_) => "dict",
        Value::Null => "string",
    }
}
#[cfg(target_os = "macos")]
fn export_domain(domain: &str, current_host: bool) -> Result<Value> {
    let mut command = std::process::Command::new("defaults");
    if current_host {
        command.arg("-currentHost");
    }
    let output = command.args(["export", domain, "-"]).output()?;
    if !output.status.success() {
        return Ok(Value::Object(Default::default()));
    }
    let plist = plist::Value::from_reader_xml(output.stdout.as_slice())?;
    Ok(crate::prefs::plist_to_json(&plist))
}

#[cfg(target_os = "macos")]
pub fn resolve_bundle_id(app: &str) -> Result<String> {
    let script = format!("id of application {:?}", app);
    let output = Command::new("osascript").args(["-e", &script]).output()?;
    if !output.status.success() {
        return Err(anyhow::anyhow!(
            "could not resolve the bundle id for {app}; pass --domain explicitly"
        ));
    }
    let id = String::from_utf8(output.stdout)?.trim().to_owned();
    if id.is_empty() {
        Err(anyhow::anyhow!(
            "could not resolve the bundle id for {app}; pass --domain explicitly"
        ))
    } else {
        Ok(id)
    }
}
#[cfg(not(target_os = "macos"))]
pub fn resolve_bundle_id(_app: &str) -> Result<String> {
    Err(anyhow!(
        "bundle-id resolution requires macOS; pass --domain explicitly"
    ))
}

fn home_dir() -> Option<PathBuf> {
    std::env::var_os("HOME").map(PathBuf::from)
}

pub fn decode_artifact(path: &Path, steps: &[serde_yaml::Value], profile: &Value) -> Result<Value> {
    let bytes = fs::read(path)?;
    let mut state = ArtifactState::default();
    crate::pipeline::decode(steps, &bytes, profile, &mut state)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn guard_is_default_closed() {
        let mut v = serde_json::json!({"safe":"hello","apiToken":"abc","blob":"0123456789abcdefghijklmnopqrstuv"});
        let redactions = redact_secrets(&mut v, &BTreeSet::new());
        assert_eq!(redactions.len(), 2);
        assert_eq!(v, serde_json::json!({"safe":"hello"}));
    }

    #[test]
    fn guard_redacts_nested_objects_and_array_values_with_metadata() {
        let mut value = serde_json::json!({
            "accounts":[{"password":"short-secret","name":"Ada"}],
            "items":["0123456789abcdefghijklmnopqrstuv", {"clientSecret":"hidden"}],
            "allowed":{"token":"explicitly-kept","nested":["0123456789abcdefghijklmnopqrstuv"]}
        });
        let include = BTreeSet::from(["allowed".to_string()]);
        let redactions = redact_secrets(&mut value, &include);

        assert_eq!(
            value,
            serde_json::json!({
                "accounts":[{"name":"Ada"}],
                "items":[null, {}],
                "allowed":{"token":"explicitly-kept","nested":["0123456789abcdefghijklmnopqrstuv"]}
            })
        );
        assert_eq!(
            serde_json::to_value(redactions).unwrap(),
            serde_json::json!([
                {"path":"accounts[0].password","reason":"sensitive_key","action":"removed"},
                {"path":"items[0]","reason":"high_entropy_string","action":"replaced_with_null"},
                {"path":"items[1].clientSecret","reason":"sensitive_key","action":"removed"}
            ])
        );
    }

    #[test]
    fn capture_diff_is_canonical_and_stable() {
        let before_one: Value =
            serde_json::from_str(r#"{"z":0,"nested":{"b":1,"a":2},"gone":true}"#).unwrap();
        let before_two: Value =
            serde_json::from_str(r#"{"gone":true,"nested":{"a":2,"b":1},"z":0}"#).unwrap();
        let after_one: Value =
            serde_json::from_str(r#"{"z":0,"added":[2,1],"nested":{"b":1,"a":3}}"#).unwrap();
        let after_two: Value =
            serde_json::from_str(r#"{"nested":{"a":3,"b":1},"added":[2,1],"z":0}"#).unwrap();

        let first = capture_diff(Some(&before_one), &after_one);
        let second = capture_diff(Some(&before_two), &after_two);
        assert_eq!(first, second);
        assert_eq!(
            first["changes"],
            serde_json::json!([
                {"op":"add","path":"$/added","after":[2,1]},
                {"op":"remove","path":"$/gone","before":true},
                {"op":"replace","path":"$/nested/a","before":2,"after":3}
            ])
        );
        assert_eq!(
            capture_diff(None, &after_two)["changes"],
            serde_json::json!([
                {"op":"add","path":"$/added","after":[2,1]},
                {"op":"add","path":"$/nested/a","after":3},
                {"op":"add","path":"$/nested/b","after":1},
                {"op":"add","path":"$/z","after":0}
            ])
        );
    }

    #[test]
    fn existing_capture_is_redacted_before_review() {
        let directory = tempfile::TempDir::new().unwrap();
        let output = directory.path().join("capture.json");
        fs::write(
            &output,
            br#"{"safe":"visible","password":"TOP-SECRET-EXISTING-VALUE"}"#,
        )
        .unwrap();

        let (existing, redactions) = read_existing_output(&output, &BTreeSet::new()).unwrap();

        assert_eq!(existing.unwrap(), serde_json::json!({"safe":"visible"}));
        assert_eq!(redactions.len(), 1);
        assert_eq!(redactions[0].path, "password");
    }

    #[test]
    fn capture_output_is_always_user_only() {
        let directory = tempfile::TempDir::new().unwrap();
        let output = directory.path().join("capture.json");

        write_capture_output(&output, &serde_json::json!({"password":"explicit"})).unwrap();

        let mode = fs::metadata(output).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o600);
    }
    #[test]
    fn sniffer_peels_encrypted_header_gzip_json() {
        let steps:Vec<serde_yaml::Value>=serde_yaml::from_str("- header: {bytes: 16, keep: false, template: MDEyMzQ1Njc4OWFiY2RlZg==}\n- aes: {algo: aes-256-cbc, optional: true, password: {default: '12345678'}, salted: false}\n- gzip: {}\n- json: {}\n").unwrap();
        let mut state = ArtifactState::default();
        state.optional_steps_applied.insert("1".into(), true);
        let artifact = crate::pipeline::encode(
            &steps,
            &serde_json::json!({"sniff":true}),
            &Value::Null,
            &mut state,
        )
        .unwrap();
        let dir = tempfile::TempDir::new().unwrap();
        let path = dir.path().join("synthetic.rayconfig");
        fs::write(&path, artifact).unwrap();
        let result = sniff(&path).unwrap();
        assert_eq!(result["verdict"], "json");
        assert_eq!(result["pipeline"].as_array().unwrap().len(), 4);
        assert_eq!(result["header_b64"], "MDEyMzQ1Njc4OWFiY2RlZg==");
        assert_eq!(result["model"], serde_json::json!({"sniff":true}));
        assert_eq!(
            result["pipeline"][1]["aes"]["password"]["default"],
            "12345678"
        );
        assert_eq!(
            result["pipeline"][1]["aes"]["password"]["profile_key"],
            "secrets.export_password"
        );
    }

    #[test]
    fn sniffer_handles_encryption_outside_the_opaque_header() {
        let steps: Vec<serde_yaml::Value> = serde_yaml::from_str(
            "- aes: {algo: aes-256-cbc, optional: false, password: {default: '12345678'}, salted: false}\n- header: {bytes: 16, keep: false, template: MDEyMzQ1Njc4OWFiY2RlZg==}\n- gzip: {}\n- json: {}\n",
        )
        .unwrap();
        let artifact = crate::pipeline::encode(
            &steps,
            &serde_json::json!({"outer_encryption":true}),
            &Value::Null,
            &mut ArtifactState::default(),
        )
        .unwrap();
        let directory = tempfile::TempDir::new().unwrap();
        let path = directory.path().join("outer.rayconfig");
        fs::write(&path, artifact).unwrap();
        let result = sniff(&path).unwrap();
        assert_eq!(result["pipeline"][0]["aes"]["algo"], "aes-256-cbc");
        assert_eq!(result["pipeline"][1]["header"]["bytes"], 16);
        assert_eq!(result["model"]["outer_encryption"], true);
    }

    #[test]
    fn sniffer_tries_the_vendor_password_for_a_salted_envelope() {
        let compressed = {
            use std::io::Write as _;
            let mut encoder =
                flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
            encoder.write_all(br#"{"salted":true}"#).unwrap();
            encoder.finish().unwrap()
        };
        let artifact =
            crate::pipeline::openssl_aes_bytes(true, "aes-256-cbc", b"12345678", true, &compressed)
                .unwrap();
        let directory = tempfile::TempDir::new().unwrap();
        let path = directory.path().join("salted.bin");
        fs::write(&path, artifact).unwrap();
        let result = sniff(&path).unwrap();
        assert_eq!(result["pipeline"][0]["aes"]["salted"], true);
        assert_eq!(result["pipeline"][1], serde_json::json!({"gzip":{}}));
        assert_eq!(result["model"]["salted"], true);
    }

    #[test]
    fn sniffer_peels_base64_and_parses_toml() {
        let directory = tempfile::TempDir::new().unwrap();
        let json_path = directory.path().join("encoded.txt");
        let encoded = base64::engine::general_purpose::STANDARD.encode(br#"{"ok":true}"#);
        fs::write(&json_path, encoded).unwrap();
        let json = sniff(&json_path).unwrap();
        assert_eq!(json["pipeline"][0], serde_json::json!({"base64":{}}));
        assert_eq!(json["pipeline"][1], serde_json::json!({"json":{}}));
        assert_eq!(json["model"]["ok"], true);

        let toml_path = directory.path().join("settings.toml");
        fs::write(&toml_path, "[window]\nopacity = 0.9\n").unwrap();
        let toml = sniff(&toml_path).unwrap();
        assert_eq!(toml["verdict"], "toml");
        assert_eq!(toml["model"]["window"]["opacity"], 0.9);
    }

    #[test]
    fn sniff_output_prefers_the_decoded_model_and_is_atomic() {
        let directory = tempfile::TempDir::new().unwrap();
        let source = directory.path().join("source.json");
        let output = directory.path().join("nested/capture.json");
        fs::write(&source, "{}").unwrap();
        assert!(review_sniff_output(
            &source,
            &output,
            &serde_json::json!({"version":1,"decoded":true,"model":{"captured":true},"redaction":{"policy":"default_closed","count":0,"items":[]}}),
            ReviewMode::AssumeYes,
            false,
        )
        .unwrap());
        let written: Value = serde_json::from_slice(&fs::read(output).unwrap()).unwrap();
        assert_eq!(written, serde_json::json!({"captured":true}));
    }
}
