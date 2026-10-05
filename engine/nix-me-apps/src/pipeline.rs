use std::collections::BTreeMap;
use std::io::{Cursor, Read, Write};

use crate::state::ArtifactState;
use aes::{Aes128, Aes256};
use anyhow::{anyhow, bail, Context, Result};
use base64::Engine as _;
use cbc::cipher::{block_padding::Pkcs7, BlockDecryptMut, BlockEncryptMut, KeyIvInit};
use flate2::{read::GzDecoder, write::GzEncoder, Compression};
use serde_json::Value;
use sha2::{Digest as _, Sha256};

#[derive(Debug)]
enum Payload {
    Bytes(Vec<u8>),
    Model(Value),
    Files(BTreeMap<String, Vec<u8>>),
}

pub fn encode(
    steps: &[serde_yaml::Value],
    model: &Value,
    profile: &Value,
    state: &mut ArtifactState,
) -> Result<Vec<u8>> {
    let mut payload = Payload::Model(model.clone());
    for (index, step) in steps.iter().enumerate().rev() {
        payload = encode_step(index, step, payload, profile, state)?;
    }
    match payload {
        Payload::Bytes(v) => Ok(v),
        _ => bail!("pipeline encode did not produce bytes"),
    }
}

pub fn decode(
    steps: &[serde_yaml::Value],
    artifact: &[u8],
    profile: &Value,
    state: &mut ArtifactState,
) -> Result<Value> {
    let mut payload = Payload::Bytes(artifact.to_vec());
    for (index, step) in steps.iter().enumerate() {
        let optional = step_options(step)
            .and_then(|m| m.get("optional"))
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        if optional {
            match decode_step(index, step, payload, profile, state) {
                Ok(next) => {
                    state.optional_steps_applied.insert(index.to_string(), true);
                    payload = next;
                }
                Err(err) => {
                    state
                        .optional_steps_applied
                        .insert(index.to_string(), false);
                    payload = err.1;
                }
            }
        } else {
            payload = decode_step(index, step, payload, profile, state).map_err(|(e, _)| e)?;
        }
    }
    match payload {
        Payload::Model(v) => Ok(v),
        Payload::Files(files) => Ok(Value::Object(
            files
                .into_iter()
                .map(|(k, v)| {
                    (
                        k,
                        Value::String(base64::engine::general_purpose::STANDARD.encode(v)),
                    )
                })
                .collect(),
        )),
        Payload::Bytes(v) => Ok(Value::String(
            String::from_utf8(v).context("pipeline terminal bytes are not UTF-8")?,
        )),
    }
}

type DecodeFailure = (anyhow::Error, Payload);
fn decode_step(
    index: usize,
    step: &serde_yaml::Value,
    payload: Payload,
    profile: &Value,
    state: &mut ArtifactState,
) -> std::result::Result<Payload, DecodeFailure> {
    let original = clone_payload(&payload);
    let result = (|| -> Result<Payload> {
        let (name, opts) = single_step(step)?;
        match name {
            "header" => {
                let mut bytes = need_bytes(payload)?;
                let count = yaml_usize(opts, "bytes")?;
                if bytes.len() < count {
                    bail!("header expects {count} bytes, artifact has {}", bytes.len());
                }
                let header = bytes.drain(..count).collect::<Vec<_>>();
                if yaml_bool(opts, "keep", true) {
                    state.header_b64 =
                        Some(base64::engine::general_purpose::STANDARD.encode(header));
                }
                Ok(Payload::Bytes(bytes))
            }
            "gzip" => {
                let bytes = need_bytes(payload)?;
                let mut out = Vec::new();
                GzDecoder::new(bytes.as_slice())
                    .read_to_end(&mut out)
                    .context("gzip decode")?;
                Ok(Payload::Bytes(out))
            }
            "base64" => {
                let bytes = need_bytes(payload)?;
                Ok(Payload::Bytes(
                    base64::engine::general_purpose::STANDARD
                        .decode(bytes)
                        .context("base64 decode")?,
                ))
            }
            "aes" => {
                let bytes = need_bytes(payload)?;
                Ok(Payload::Bytes(openssl_aes(false, opts, &bytes, profile)?))
            }
            "json" => Ok(Payload::Model(
                serde_json::from_slice(&need_bytes(payload)?).context("JSON decode")?,
            )),
            "yaml" => {
                let y: serde_yaml::Value = serde_yaml::from_slice(&need_bytes(payload)?)?;
                Ok(Payload::Model(serde_json::to_value(y)?))
            }
            "toml" => {
                let text = String::from_utf8(need_bytes(payload)?)?;
                let v: toml::Value = toml::from_str(&text)?;
                Ok(Payload::Model(serde_json::to_value(v)?))
            }
            "plist" => {
                let bytes = need_bytes(payload)?;
                let v = plist::Value::from_reader(Cursor::new(bytes))?;
                Ok(Payload::Model(crate::prefs::plist_to_json(&v)))
            }
            "zip" => decode_zip(need_bytes(payload)?, opts),
            "tar" => decode_tar(need_bytes(payload)?, opts),
            "sqlite" => bail!("sqlite is a v2 pipeline primitive and is not implemented"),
            other => bail!("unknown pipeline primitive {other} at step {index}"),
        }
    })();
    result.map_err(|e| (e, original))
}

fn encode_step(
    index: usize,
    step: &serde_yaml::Value,
    payload: Payload,
    profile: &Value,
    state: &mut ArtifactState,
) -> Result<Payload> {
    let (name, opts) = single_step(step)?;
    if yaml_bool(opts, "optional", false)
        && !state
            .optional_steps_applied
            .get(&index.to_string())
            .copied()
            .unwrap_or(false)
    {
        return Ok(payload);
    }
    match name {
        "header" => {
            let bytes = need_bytes(payload)?;
            let count = yaml_usize(opts, "bytes")?;
            let mut header = state
                .header_b64
                .as_deref()
                .and_then(|v| base64::engine::general_purpose::STANDARD.decode(v).ok())
                .or_else(|| {
                    opts.get("template")
                        .and_then(|v| v.as_str())
                        .and_then(load_template)
                })
                .ok_or_else(|| anyhow!("header step needs preserved header state or template"))?;
            if header.len() != count {
                bail!(
                    "header template has {} bytes; expected {count}",
                    header.len()
                );
            }
            header.extend(bytes);
            Ok(Payload::Bytes(header))
        }
        "gzip" => {
            let bytes = need_bytes(payload)?;
            let mut encoder = GzEncoder::new(Vec::new(), Compression::default());
            encoder.write_all(&bytes)?;
            Ok(Payload::Bytes(encoder.finish()?))
        }
        "base64" => Ok(Payload::Bytes(
            base64::engine::general_purpose::STANDARD
                .encode(need_bytes(payload)?)
                .into_bytes(),
        )),
        "aes" => Ok(Payload::Bytes(openssl_aes(
            true,
            opts,
            &need_bytes(payload)?,
            profile,
        )?)),
        "json" => Ok(Payload::Bytes(serde_json::to_vec_pretty(&need_model(
            payload,
        )?)?)),
        "yaml" => Ok(Payload::Bytes(
            serde_yaml::to_string(&need_model(payload)?)?.into_bytes(),
        )),
        "toml" => {
            let v = need_model(payload)?;
            Ok(Payload::Bytes(toml::to_string_pretty(&v)?.into_bytes()))
        }
        "plist" => {
            let v = crate::prefs::json_to_plist(&need_model(payload)?)?;
            let flavor = opts
                .get("flavor")
                .and_then(|v| v.as_str())
                .unwrap_or("auto");
            let mut out = Vec::new();
            if flavor == "binary" {
                plist::to_writer_binary(&mut out, &v)?;
            } else {
                plist::to_writer_xml(&mut out, &v)?;
            }
            Ok(Payload::Bytes(out))
        }
        "zip" => encode_zip(payload, opts),
        "tar" => encode_tar(payload, opts),
        "sqlite" => bail!("sqlite is a v2 pipeline primitive and is not implemented"),
        other => bail!("unknown pipeline primitive {other} at step {index}"),
    }
}

fn single_step(step: &serde_yaml::Value) -> Result<(&str, &serde_yaml::Mapping)> {
    let map = step
        .as_mapping()
        .ok_or_else(|| anyhow!("pipeline step must be a map"))?;
    if map.len() != 1 {
        bail!("pipeline step must have exactly one primitive");
    }
    let (name, opts) = map.iter().next().unwrap();
    Ok((
        name.as_str()
            .ok_or_else(|| anyhow!("pipeline primitive name must be a string"))?,
        opts.as_mapping()
            .ok_or_else(|| anyhow!("pipeline primitive options must be a map"))?,
    ))
}
fn step_options(step: &serde_yaml::Value) -> Option<&serde_yaml::Mapping> {
    step.as_mapping()?.iter().next()?.1.as_mapping()
}
fn key(name: &str) -> serde_yaml::Value {
    serde_yaml::Value::String(name.into())
}
fn yaml_bool(opts: &serde_yaml::Mapping, name: &str, default: bool) -> bool {
    opts.get(key(name))
        .and_then(|v| v.as_bool())
        .unwrap_or(default)
}
fn yaml_usize(opts: &serde_yaml::Mapping, name: &str) -> Result<usize> {
    opts.get(key(name))
        .and_then(|v| v.as_u64())
        .map(|v| v as usize)
        .ok_or_else(|| anyhow!("pipeline option {name} must be an integer"))
}
fn need_bytes(payload: Payload) -> Result<Vec<u8>> {
    match payload {
        Payload::Bytes(v) => Ok(v),
        _ => bail!("pipeline primitive expected bytes"),
    }
}
fn need_model(payload: Payload) -> Result<Value> {
    match payload {
        Payload::Model(v) => Ok(v),
        _ => bail!("pipeline primitive expected structured model"),
    }
}
fn clone_payload(p: &Payload) -> Payload {
    match p {
        Payload::Bytes(v) => Payload::Bytes(v.clone()),
        Payload::Model(v) => Payload::Model(v.clone()),
        Payload::Files(v) => Payload::Files(v.clone()),
    }
}
fn load_template(value: &str) -> Option<Vec<u8>> {
    base64::engine::general_purpose::STANDARD
        .decode(value)
        .ok()
        .or_else(|| std::fs::read(value).ok())
}

fn select_names(opts: &serde_yaml::Mapping) -> Vec<String> {
    opts.get(key("select"))
        .and_then(|v| v.as_sequence())
        .map(|s| {
            s.iter()
                .filter_map(|v| v.as_str().map(str::to_owned))
                .collect()
        })
        .unwrap_or_default()
}
fn decode_zip(bytes: Vec<u8>, opts: &serde_yaml::Mapping) -> Result<Payload> {
    let mut archive = zip::ZipArchive::new(Cursor::new(bytes))?;
    let select = select_names(opts);
    let mut files = BTreeMap::new();
    for i in 0..archive.len() {
        let mut file = archive.by_index(i)?;
        if file.is_dir() {
            continue;
        }
        let name = file.name().to_owned();
        if select.is_empty() || select.contains(&name) {
            let mut data = Vec::new();
            file.read_to_end(&mut data)?;
            files.insert(name, data);
        }
    }
    if files.len() == 1 {
        Ok(Payload::Bytes(files.into_values().next().unwrap()))
    } else {
        Ok(Payload::Files(files))
    }
}
fn decode_tar(bytes: Vec<u8>, opts: &serde_yaml::Mapping) -> Result<Payload> {
    let mut archive = tar::Archive::new(Cursor::new(bytes));
    let select = select_names(opts);
    let mut files = BTreeMap::new();
    for item in archive.entries()? {
        let mut file = item?;
        if !file.header().entry_type().is_file() {
            continue;
        }
        let name = file.path()?.to_string_lossy().into_owned();
        if select.is_empty() || select.contains(&name) {
            let mut data = Vec::new();
            file.read_to_end(&mut data)?;
            files.insert(name, data);
        }
    }
    if files.len() == 1 {
        Ok(Payload::Bytes(files.into_values().next().unwrap()))
    } else {
        Ok(Payload::Files(files))
    }
}
fn into_files(payload: Payload, opts: &serde_yaml::Mapping) -> Result<BTreeMap<String, Vec<u8>>> {
    match payload {
        Payload::Files(v) => Ok(v),
        Payload::Bytes(v) => {
            let names = select_names(opts);
            if names.len() != 1 {
                bail!("container encode from bytes requires exactly one select path");
            }
            Ok([(names[0].clone(), v)].into())
        }
        _ => bail!("container primitive expected bytes or file map"),
    }
}
fn encode_zip(payload: Payload, opts: &serde_yaml::Mapping) -> Result<Payload> {
    let files = into_files(payload, opts)?;
    let cursor = Cursor::new(Vec::new());
    let mut zip = zip::ZipWriter::new(cursor);
    for (name, data) in files {
        zip.start_file(
            name,
            zip::write::FileOptions::default().compression_method(zip::CompressionMethod::Deflated),
        )?;
        zip.write_all(&data)?;
    }
    Ok(Payload::Bytes(zip.finish()?.into_inner()))
}
fn encode_tar(payload: Payload, opts: &serde_yaml::Mapping) -> Result<Payload> {
    let files = into_files(payload, opts)?;
    let mut out = Vec::new();
    {
        let mut tar = tar::Builder::new(&mut out);
        for (name, data) in files {
            let mut header = tar::Header::new_gnu();
            header.set_size(data.len() as u64);
            header.set_mode(0o644);
            header.set_cksum();
            tar.append_data(&mut header, name, data.as_slice())?;
        }
        tar.finish()?;
    }
    Ok(Payload::Bytes(out))
}

fn openssl_aes(
    encode: bool,
    opts: &serde_yaml::Mapping,
    input: &[u8],
    profile: &Value,
) -> Result<Vec<u8>> {
    let algo = opts
        .get(key("algo"))
        .and_then(|v| v.as_str())
        .ok_or_else(|| anyhow!("aes.algo is required"))?;
    if algo == "aes-256-gcm" {
        bail!("aes-256-gcm requires a compiled codec in pipeline v1");
    }
    let pass_opts = opts.get(key("password")).and_then(|v| v.as_mapping());
    let profile_key = pass_opts
        .and_then(|m| m.get(key("profile_key")))
        .and_then(|v| v.as_str());
    let password = profile_key
        .and_then(|path| lookup_profile(profile, path))
        .and_then(|v| v.as_str())
        .map(str::to_owned)
        .or_else(|| {
            pass_opts
                .and_then(|m| m.get(key("default")))
                .and_then(|v| v.as_str())
                .map(str::to_owned)
        })
        .ok_or_else(|| anyhow!("AES password is unavailable"))?;
    openssl_aes_bytes(
        encode,
        algo,
        password.as_bytes(),
        yaml_bool(opts, "salted", false),
        input,
    )
}

pub(crate) fn openssl_aes_bytes(
    encode: bool,
    algo: &str,
    password: &[u8],
    salted: bool,
    input: &[u8],
) -> Result<Vec<u8>> {
    let (payload, salt) = if encode {
        if salted {
            let mut salt = [0u8; 8];
            getrandom::getrandom(&mut salt)
                .map_err(|error| anyhow!("generate AES salt: {error}"))?;
            (input, Some(salt))
        } else {
            (input, None)
        }
    } else if salted {
        if input.len() < 16 || &input[..8] != b"Salted__" {
            bail!("AES input is missing the OpenSSL Salted__ envelope");
        }
        (&input[16..], Some(input[8..16].try_into().unwrap()))
    } else {
        (input, None)
    };
    let key_len = match algo {
        "aes-256-cbc" => 32,
        "aes-128-cbc" => 16,
        "aes-256-gcm" => bail!("aes-256-gcm requires a compiled codec in pipeline v1"),
        other => bail!("unsupported AES algorithm {other}"),
    };
    let (key, iv) = evp_bytes_to_key(password, salt.as_ref().map(|v| v.as_slice()), key_len);
    let transformed = match (algo, encode) {
        ("aes-256-cbc", true) => cbc::Encryptor::<Aes256>::new_from_slices(&key, &iv)?
            .encrypt_padded_vec_mut::<Pkcs7>(payload),
        ("aes-256-cbc", false) => cbc::Decryptor::<Aes256>::new_from_slices(&key, &iv)?
            .decrypt_padded_vec_mut::<Pkcs7>(payload)
            .map_err(|_| anyhow!("AES-256-CBC padding or password is invalid"))?,
        ("aes-128-cbc", true) => cbc::Encryptor::<Aes128>::new_from_slices(&key, &iv)?
            .encrypt_padded_vec_mut::<Pkcs7>(payload),
        ("aes-128-cbc", false) => cbc::Decryptor::<Aes128>::new_from_slices(&key, &iv)?
            .decrypt_padded_vec_mut::<Pkcs7>(payload)
            .map_err(|_| anyhow!("AES-128-CBC padding or password is invalid"))?,
        _ => unreachable!(),
    };
    if encode && salted {
        let mut envelope = b"Salted__".to_vec();
        envelope.extend_from_slice(salt.as_ref().unwrap());
        envelope.extend(transformed);
        Ok(envelope)
    } else {
        Ok(transformed)
    }
}

fn evp_bytes_to_key(password: &[u8], salt: Option<&[u8]>, key_len: usize) -> (Vec<u8>, [u8; 16]) {
    let mut material = Vec::new();
    let mut previous = Vec::new();
    while material.len() < key_len + 16 {
        // OpenSSL 1.1+ and 3.x use SHA-256 for `enc -k` unless `-md` is
        // overridden. The recipe format models that current default.
        let mut digest = Sha256::new();
        if !previous.is_empty() {
            digest.update(&previous);
        }
        digest.update(password);
        if let Some(salt) = salt {
            digest.update(salt);
        }
        previous = digest.finalize().to_vec();
        material.extend_from_slice(&previous);
    }
    let key = material[..key_len].to_vec();
    let mut iv = [0u8; 16];
    iv.copy_from_slice(&material[key_len..key_len + 16]);
    (key, iv)
}
fn lookup_profile<'a>(profile: &'a Value, path: &str) -> Option<&'a Value> {
    let mut cur = profile;
    for part in path.strip_prefix("profile.").unwrap_or(path).split('.') {
        cur = cur.get(part)?;
    }
    Some(cur)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn header_gzip_json_round_trip() {
        let steps: Vec<serde_yaml::Value> =
            serde_yaml::from_str("- header: {bytes: 4, keep: true}\n- gzip: {}\n- json: {}\n")
                .unwrap();
        let model = serde_json::json!({"hello":"world"});
        let mut state = ArtifactState {
            header_b64: Some(base64::engine::general_purpose::STANDARD.encode(b"HEAD")),
            ..Default::default()
        };
        let encoded = encode(&steps, &model, &Value::Null, &mut state).unwrap();
        let decoded = decode(&steps, &encoded, &Value::Null, &mut state).unwrap();
        assert_eq!(decoded, model);
        assert!(encoded.starts_with(b"HEAD"));
    }
    #[test]
    fn optional_envelope_reproduction_records_a_skipped_aes_layer() {
        let steps:Vec<serde_yaml::Value>=serde_yaml::from_str("- header: {bytes: 4, keep: true}\n- aes: {algo: aes-256-cbc, optional: true, password: {default: test}, salted: false}\n- gzip: {}\n- json: {}\n").unwrap();
        let model = serde_json::json!({"plain":true});
        let mut state = ArtifactState {
            header_b64: Some(base64::engine::general_purpose::STANDARD.encode(b"HEAD")),
            ..Default::default()
        };
        let encoded = encode(&steps, &model, &Value::Null, &mut state).unwrap();
        let decoded = decode(&steps, &encoded, &Value::Null, &mut state).unwrap();
        assert_eq!(decoded, model);
        assert_eq!(state.optional_steps_applied.get("1"), Some(&false));
        let encoded_again = encode(&steps, &model, &Value::Null, &mut state).unwrap();
        assert_eq!(
            decode(&steps, &encoded_again, &Value::Null, &mut state).unwrap(),
            model
        );
    }
    #[test]
    fn aes_cbc_variants_round_trip_openssl_envelopes() {
        for algo in ["aes-128-cbc", "aes-256-cbc"] {
            for salted in [false, true] {
                let plain = b"pipeline payload";
                let encrypted = openssl_aes_bytes(true, algo, b"12345678", salted, plain).unwrap();
                assert_ne!(encrypted, plain);
                if salted {
                    assert!(encrypted.starts_with(b"Salted__"));
                }
                let decrypted =
                    openssl_aes_bytes(false, algo, b"12345678", salted, &encrypted).unwrap();
                assert_eq!(decrypted, plain);
            }
        }
    }
    #[test]
    fn aes_cbc_matches_openssl_sha256_vectors() {
        let plain = b"nix-me pipeline vector";
        let aes256 = decode_hex("15208ac6240bd47d17156b4ff9d748f6e95bda303dfa4ecdb0554a6aad0364d9");
        let aes128 = decode_hex("3dc2096297eeaa56bf150c642789466b01e5690aa3dc14599d4b59235f6a18c4");
        assert_eq!(
            openssl_aes_bytes(true, "aes-256-cbc", b"12345678", false, plain).unwrap(),
            aes256
        );
        assert_eq!(
            openssl_aes_bytes(true, "aes-128-cbc", b"12345678", false, plain).unwrap(),
            aes128
        );

        let salted = base64::engine::general_purpose::STANDARD
            .decode("U2FsdGVkX191Vf1JSFRtbfWC0n97SoHUzh/eGCpN8aBOD9H4jokVQoePONYNq4w5")
            .unwrap();
        assert_eq!(
            openssl_aes_bytes(false, "aes-256-cbc", b"12345678", true, &salted).unwrap(),
            plain
        );
    }
    #[test]
    fn aes_password_prefers_the_profile_key() {
        let steps: Vec<serde_yaml::Value> = serde_yaml::from_str(
            "- aes: {algo: aes-256-cbc, password: {default: wrong, profile_key: secrets.password}, salted: false}\n- json: {}\n",
        )
        .unwrap();
        let model = serde_json::json!({"profile_password":true});
        let profile = serde_json::json!({"secrets":{"password":"correct"}});
        let encoded = encode(&steps, &model, &profile, &mut ArtifactState::default()).unwrap();
        let decrypted =
            openssl_aes_bytes(false, "aes-256-cbc", b"correct", false, &encoded).unwrap();
        assert_eq!(serde_json::from_slice::<Value>(&decrypted).unwrap(), model);
        assert!(openssl_aes_bytes(false, "aes-256-cbc", b"wrong", false, &encoded).is_err());
    }

    fn decode_hex(input: &str) -> Vec<u8> {
        input
            .as_bytes()
            .chunks_exact(2)
            .map(|pair| {
                let text = std::str::from_utf8(pair).unwrap();
                u8::from_str_radix(text, 16).unwrap()
            })
            .collect()
    }
}
