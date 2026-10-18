use std::collections::BTreeSet;

use anyhow::{anyhow, bail, Result};
use serde_json::{Map, Value};

/// Validate an RFC 6901 JSON-pointer allowlist.
///
/// The root pointer is deliberately forbidden: allowing it would turn an
/// allowlist into whole-document ownership. Overlapping paths are rejected so
/// ownership remains deterministic and reviewable.
pub fn validate_allowlist(paths: &[String]) -> Result<()> {
    if paths.is_empty() {
        bail!("path allowlist must contain at least one JSON pointer");
    }
    let mut seen = BTreeSet::new();
    for path in paths {
        validate_pointer(path)?;
        if !seen.insert(path) {
            bail!("duplicate allowlisted path {path}");
        }
    }
    for (index, left) in paths.iter().enumerate() {
        for right in paths.iter().skip(index + 1) {
            if paths_overlap(left, right) {
                bail!("overlapping allowlisted paths {left} and {right}");
            }
        }
    }
    Ok(())
}

/// Assert that sensitive paths cannot be reached through an allowed parent.
pub fn assert_disjoint(allowed: &[String], sensitive: &[String]) -> Result<()> {
    for path in sensitive {
        validate_pointer(path)?;
    }
    for allowed_path in allowed {
        for sensitive_path in sensitive {
            if paths_overlap(allowed_path, sensitive_path) {
                bail!("allowlisted path {allowed_path} overlaps sensitive path {sensitive_path}");
            }
        }
    }
    Ok(())
}

/// Copy only explicitly allowlisted paths from a JSON value.
pub fn project_paths(source: &Value, paths: &[String]) -> Result<Value> {
    validate_allowlist(paths)?;
    let mut projected = Value::Object(Map::new());
    for path in paths {
        if let Some(value) = source.pointer(path) {
            set_pointer(&mut projected, path, value.clone())?;
        }
    }
    Ok(projected)
}

/// Merge a patch into a document, refusing every leaf outside the allowlist.
pub fn merge_allowlisted(target: &mut Value, patch: &Value, paths: &[String]) -> Result<()> {
    validate_allowlist(paths)?;
    let leaves = leaf_paths(patch);
    if leaves.is_empty() && patch != &Value::Object(Map::new()) {
        bail!("allowlisted patch contains no addressable values");
    }
    for (path, value) in leaves {
        if !paths.iter().any(|allowed| path_is_within(&path, allowed)) {
            bail!("patch path {path} is not allowlisted");
        }
        set_pointer(target, &path, value.clone())?;
    }
    Ok(())
}

/// Project `actual` to the leaves present in `expected` and compare values.
pub fn assert_semantic_readback(actual: &Value, expected: &Value, paths: &[String]) -> Result<()> {
    validate_allowlist(paths)?;
    let mut readback = Value::Object(Map::new());
    for (path, _) in leaf_paths(expected) {
        if !paths.iter().any(|allowed| path_is_within(&path, allowed)) {
            bail!("expected path {path} is not allowlisted");
        }
        let value = actual
            .pointer(&path)
            .ok_or_else(|| anyhow!("semantic read-back is missing {path}"))?;
        set_pointer(&mut readback, &path, value.clone())?;
    }
    if &readback != expected {
        bail!("semantic read-back differs from the requested allowlisted model");
    }
    Ok(())
}

/// Fail if a captured or requested value contains a declared sensitive path.
pub fn assert_paths_absent(value: &Value, sensitive: &[String]) -> Result<()> {
    for path in sensitive {
        validate_pointer(path)?;
        if value.pointer(path).is_some() {
            bail!("redaction assertion failed: sensitive path {path} is present");
        }
    }
    Ok(())
}

pub fn validate_pointer(path: &str) -> Result<()> {
    if path.is_empty() {
        bail!("the JSON-pointer root cannot be allowlisted");
    }
    if !path.starts_with('/') {
        bail!("path {path:?} must be an RFC 6901 JSON pointer beginning with '/'");
    }
    for segment in path.split('/').skip(1) {
        let bytes = segment.as_bytes();
        let mut index = 0;
        while index < bytes.len() {
            if bytes[index] == b'~' {
                if index + 1 >= bytes.len() || !matches!(bytes[index + 1], b'0' | b'1') {
                    bail!("path {path:?} contains an invalid JSON-pointer escape");
                }
                index += 2;
            } else {
                index += 1;
            }
        }
        let decoded = unescape_segment(segment)?;
        if decoded == "-"
            || (!decoded.is_empty() && decoded.bytes().all(|byte| byte.is_ascii_digit()))
        {
            bail!(
                "path {path:?} contains numeric array traversal, which is unsupported and refused"
            );
        }
    }
    Ok(())
}

pub fn path_is_within(path: &str, parent: &str) -> bool {
    path == parent
        || path
            .strip_prefix(parent)
            .is_some_and(|rest| rest.starts_with('/'))
}

fn paths_overlap(left: &str, right: &str) -> bool {
    path_is_within(left, right) || path_is_within(right, left)
}

fn leaf_paths(value: &Value) -> Vec<(String, &Value)> {
    let mut leaves = Vec::new();
    collect_leaves(value, "", &mut leaves);
    leaves
}

fn collect_leaves<'a>(value: &'a Value, path: &str, leaves: &mut Vec<(String, &'a Value)>) {
    match value {
        Value::Object(map) if !map.is_empty() => {
            let mut keys = map.keys().collect::<Vec<_>>();
            keys.sort();
            for key in keys {
                let child = format!("{path}/{}", escape_segment(key));
                collect_leaves(&map[key], &child, leaves);
            }
        }
        _ if !path.is_empty() => leaves.push((path.to_owned(), value)),
        _ => {}
    }
}

fn set_pointer(target: &mut Value, path: &str, value: Value) -> Result<()> {
    validate_pointer(path)?;
    let segments = path
        .split('/')
        .skip(1)
        .map(unescape_segment)
        .collect::<Result<Vec<_>>>()?;
    let (last, parents) = segments
        .split_last()
        .ok_or_else(|| anyhow!("cannot assign the JSON-pointer root"))?;
    let mut current = target;
    for segment in parents {
        let map = current
            .as_object_mut()
            .ok_or_else(|| anyhow!("cannot descend through non-object path segment {segment}"))?;
        current = map
            .entry(segment.clone())
            .or_insert_with(|| Value::Object(Map::new()));
    }
    let map = current
        .as_object_mut()
        .ok_or_else(|| anyhow!("cannot assign child of a non-object value"))?;
    map.insert(last.clone(), value);
    Ok(())
}

fn escape_segment(segment: &str) -> String {
    segment.replace('~', "~0").replace('/', "~1")
}

fn unescape_segment(segment: &str) -> Result<String> {
    let mut output = String::new();
    let mut chars = segment.chars();
    while let Some(character) = chars.next() {
        if character != '~' {
            output.push(character);
            continue;
        }
        match chars.next() {
            Some('0') => output.push('~'),
            Some('1') => output.push('/'),
            _ => bail!("invalid JSON-pointer escape in segment {segment:?}"),
        }
    }
    Ok(output)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn projection_and_merge_are_allowlisted_and_deterministic() {
        let source = json!({
            "appearance":{"theme":"dark","zoom":1},
            "auth":{"token":"secret"},
            "slash/key":{"enabled":true}
        });
        let paths = vec![
            "/appearance/theme".to_owned(),
            "/slash~1key/enabled".to_owned(),
        ];
        assert_eq!(
            project_paths(&source, &paths).unwrap(),
            json!({"appearance":{"theme":"dark"},"slash/key":{"enabled":true}})
        );

        let mut target = source;
        merge_allowlisted(
            &mut target,
            &json!({"appearance":{"theme":"light"}}),
            &paths,
        )
        .unwrap();
        assert_eq!(target["appearance"]["theme"], "light");
        assert_eq!(target["appearance"]["zoom"], 1);
        assert_eq!(target["auth"]["token"], "secret");
        assert!(merge_allowlisted(&mut target, &json!({"auth":{"token":"leak"}}), &paths).is_err());
    }

    #[test]
    fn overlapping_and_sensitive_paths_fail_closed() {
        assert!(validate_allowlist(&["/a".into(), "/a/b".into()]).is_err());
        assert!(validate_allowlist(&[]).is_err());
        assert!(assert_disjoint(&["/account".into()], &["/account/token".into()]).is_err());
        assert!(assert_paths_absent(&json!({"token":"x"}), &["/token".into()]).is_err());
        assert!(validate_allowlist(&["/items/0".into()]).is_err());
        assert!(validate_allowlist(&["/items/-".into()]).is_err());
        assert!(validate_allowlist(&["/items/01".into()]).is_err());
    }

    #[test]
    fn semantic_readback_compares_only_requested_leaves() {
        let paths = vec!["/appearance".to_owned()];
        let expected = json!({"appearance":{"theme":"dark"}});
        let actual = json!({"appearance":{"theme":"dark","zoom":2},"private":true});
        assert_semantic_readback(&actual, &expected, &paths).unwrap();
        assert!(assert_semantic_readback(
            &json!({"appearance":{"theme":"light"}}),
            &expected,
            &paths
        )
        .is_err());
    }
}
