use crate::state::ArtifactState;
#[cfg(not(target_os = "macos"))]
use anyhow::anyhow;
use anyhow::{Context, Result};
use base64::Engine as _;
use regex::Regex;
use serde_json::Value;
use std::collections::BTreeSet;
use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{Duration, SystemTime};

pub fn sniff(path: &Path) -> Result<Value> {
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
    Ok(serde_json::json!({
        "version":1,
        "file":path,
        "offset":offset,
        "header_b64":header_b64,
        "pipeline":pipeline,
        "verdict":verdict,
        "model":model
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

pub fn redact_secrets(value: &mut Value, include: &BTreeSet<String>) -> Vec<String> {
    let pattern =
        Regex::new("(?i)(token|password|secret|credential|api[_-]?key|private[_-]?key)").unwrap();
    let mut dropped = Vec::new();
    redact_walk(value, "", include, &pattern, &mut dropped);
    dropped
}
fn redact_walk(
    value: &mut Value,
    path: &str,
    include: &BTreeSet<String>,
    pattern: &Regex,
    dropped: &mut Vec<String>,
) {
    if let Value::Object(map) = value {
        let keys = map.keys().cloned().collect::<Vec<_>>();
        for key in keys {
            let child = if path.is_empty() {
                key.clone()
            } else {
                format!("{path}.{key}")
            };
            let secret_name = pattern.is_match(&key);
            let high_entropy = map
                .get(&key)
                .and_then(|v| v.as_str())
                .map(is_high_entropy)
                .unwrap_or(false);
            if (secret_name || high_entropy) && !include.contains(&key) && !include.contains(&child)
            {
                map.remove(&key);
                dropped.push(child);
            } else if let Some(v) = map.get_mut(&key) {
                redact_walk(v, &child, include, pattern, dropped);
            }
        }
    } else if let Value::Array(items) = value {
        for (i, v) in items.iter_mut().enumerate() {
            redact_walk(v, &format!("{path}[{i}]"), include, pattern, dropped);
        }
    }
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
        let before_any = export_domain(domain, false)?;
        let before_current = export_domain(domain, true)?;
        if watch {
            watch_preference_session(app, domain, &before_any, &before_current, poll_ms)?;
        } else {
            eprintln!("Change {app} in its GUI, then press Enter.");
            io::stdin().read_line(&mut String::new())?;
        }
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
        let dropped = redact_secrets(&mut values, include);
        eprint!("Where in the UI did you make this change? ");
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
            serde_json::json!({"version":1,"recipe_fragment":{"schema_version":1,"id":id,"name":app,"bundle_id":domain,"detect":{"app_path":app_path},"sandboxed":sandboxed,"requires":if sandboxed{vec!["full_disk_access"]}else{Vec::<&str>::new()},"config":[{"kind":"defaults","domain":domain,"keys":keys,"unknown_keys":"passthrough"}],"apply":{"poke":"restart_app"},"verified":null},"profile_fragment":{(id):values},"dropped":dropped}),
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

    eprintln!("Watching {app} preferences; press Enter to finish and emit one batched capture.");
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

pub fn write_sniff_output(path: &Path, result: &Value) -> Result<()> {
    let output = result
        .get("model")
        .filter(|value| !value.is_null())
        .unwrap_or(result);
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
    fs::write(&temporary, serde_json::to_vec_pretty(output)?)?;
    fs::rename(&temporary, path)?;
    Ok(())
}

pub fn watch_artifact(
    source: &Path,
    output: Option<&Path>,
    commit: bool,
    poll_ms: u64,
    json: bool,
) -> Result<i32> {
    if commit && output.is_none() {
        return Err(anyhow::anyhow!("--commit requires --output"));
    }
    eprintln!(
        "Watching {} for changes; press Ctrl-C to stop.",
        source.display()
    );
    let mut last_modified = None;
    loop {
        let modified = fs::metadata(source)
            .with_context(|| format!("inspect artifact {}", source.display()))?
            .modified()
            .unwrap_or(SystemTime::UNIX_EPOCH);
        if last_modified != Some(modified) {
            let result = sniff(source)?;
            if let Some(path) = output {
                write_sniff_output(path, &result)?;
                if commit {
                    commit_capture(path)?;
                }
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
        let dropped = redact_secrets(&mut v, &BTreeSet::new());
        assert_eq!(dropped.len(), 2);
        assert_eq!(v, serde_json::json!({"safe":"hello"}));
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
        let output = directory.path().join("nested/capture.json");
        write_sniff_output(
            &output,
            &serde_json::json!({"version":1,"model":{"captured":true}}),
        )
        .unwrap();
        let written: Value = serde_json::from_slice(&fs::read(output).unwrap()).unwrap();
        assert_eq!(written, serde_json::json!({"captured":true}));
    }
}
