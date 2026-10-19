use std::collections::BTreeSet;

use anyhow::{anyhow, bail, Context, Result};
use serde_json::{Map, Value};

use crate::json::{assert_semantic_readback, merge_allowlisted, project_paths};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LineFormat {
    Ini,
    KeyValue,
}

#[derive(Debug, Clone)]
pub struct LineDocument {
    format: LineFormat,
    lines: Vec<Line>,
    preferred_newline: String,
}

#[derive(Debug, Clone)]
struct Line {
    raw: String,
    pair: Option<Pair>,
    section_header: Option<String>,
}

#[derive(Debug, Clone)]
struct Pair {
    path: String,
    prefix: String,
    suffix: String,
    value: String,
    quote: Option<char>,
}

impl LineDocument {
    pub fn parse(format: LineFormat, bytes: &[u8]) -> Result<Self> {
        let source = std::str::from_utf8(bytes).context("line settings file is not UTF-8")?;
        let preferred_newline = if source.contains("\r\n") {
            "\r\n"
        } else {
            "\n"
        }
        .to_owned();
        let mut section = None;
        let mut lines = Vec::new();
        let mut seen = BTreeSet::new();

        for (index, raw) in split_lines(source).into_iter().enumerate() {
            let (content, _) = content_and_ending(&raw);
            if has_unescaped_continuation(content) {
                bail!("line continuations are ambiguous and unsupported");
            }
            let syntax = if index == 0 {
                content.strip_prefix('\u{feff}').unwrap_or(content)
            } else {
                content
            };
            let section_header = if format == LineFormat::Ini {
                parse_section_header(syntax)?
            } else {
                None
            };
            if let Some(name) = &section_header {
                section = Some(name.to_owned());
            }
            let pair = parse_pair(format, &raw, section.as_deref(), index == 0)?;
            if let Some(pair) = &pair {
                if !seen.insert(pair.path.clone()) {
                    bail!("duplicate line-setting path {}", pair.path);
                }
            }
            lines.push(Line {
                raw,
                pair,
                section_header,
            });
        }
        Ok(Self {
            format,
            lines,
            preferred_newline,
        })
    }

    pub fn model(&self) -> Result<Value> {
        let mut root = Value::Object(Map::new());
        for line in &self.lines {
            let Some(pair) = &line.pair else {
                continue;
            };
            set_string_pointer(&mut root, &pair.path, pair.value.clone())?;
        }
        Ok(root)
    }

    pub fn project(&self, allowlist: &[String]) -> Result<Value> {
        project_paths(&self.model()?, allowlist)
    }

    /// Patch only allowlisted scalar keys while preserving every untouched byte.
    pub fn patch(&mut self, desired: &Value, allowlist: &[String]) -> Result<()> {
        let current = self.model()?;
        let mut merged = current.clone();
        merge_allowlisted(&mut merged, desired, allowlist)?;

        for path in allowlist {
            let before = current.pointer(path);
            let after = merged.pointer(path);
            if before == after {
                continue;
            }
            let value = after
                .and_then(Value::as_str)
                .ok_or_else(|| anyhow!("line-setting path {path} must contain a string"))?;
            self.set_pair(path, value)?;
        }
        let readback = self.model()?;
        assert_semantic_readback(&readback, desired, allowlist)
    }

    pub fn render(&self) -> Vec<u8> {
        self.lines
            .iter()
            .flat_map(|line| line.raw.as_bytes())
            .copied()
            .collect()
    }

    fn set_pair(&mut self, path: &str, value: &str) -> Result<()> {
        if let Some(line) = self
            .lines
            .iter_mut()
            .find(|line| line.pair.as_ref().is_some_and(|pair| pair.path == path))
        {
            let pair = line.pair.as_mut().expect("pair checked above");
            pair.value = value.to_owned();
            line.raw = format!(
                "{}{}{}",
                pair.prefix,
                encode_line_value(value, pair.quote),
                pair.suffix
            );
            return Ok(());
        }

        match self.format {
            LineFormat::KeyValue => {
                let key = key_value_key(path)?;
                self.ensure_trailing_newline();
                self.lines
                    .push(new_pair_line(path, &key, value, &self.preferred_newline));
            }
            LineFormat::Ini => {
                let location = ini_location(path)?;
                match location {
                    IniLocation::Global(key) => {
                        let index = self
                            .lines
                            .iter()
                            .position(|line| line.section_header.is_some())
                            .unwrap_or(self.lines.len());
                        self.ensure_newline_before(index);
                        self.lines.insert(
                            index,
                            new_pair_line(path, &key, value, &self.preferred_newline),
                        );
                    }
                    IniLocation::Section { section, key } => {
                        if let Some(header) = self.lines.iter().position(|line| {
                            line.section_header.as_deref() == Some(section.as_str())
                        }) {
                            let index = self.lines[header + 1..]
                                .iter()
                                .position(|line| line.section_header.is_some())
                                .map(|offset| header + 1 + offset)
                                .unwrap_or(self.lines.len());
                            self.ensure_newline_before(index);
                            self.lines.insert(
                                index,
                                new_pair_line(path, &key, value, &self.preferred_newline),
                            );
                        } else {
                            self.ensure_trailing_newline();
                            if self.lines.last().is_some_and(|line| {
                                !content_and_ending(&line.raw).0.trim().is_empty()
                            }) {
                                self.lines.push(Line {
                                    raw: self.preferred_newline.clone(),
                                    pair: None,
                                    section_header: None,
                                });
                            }
                            self.lines.push(Line {
                                raw: format!("[{section}]{}", self.preferred_newline),
                                pair: None,
                                section_header: Some(section),
                            });
                            self.lines.push(new_pair_line(
                                path,
                                &key,
                                value,
                                &self.preferred_newline,
                            ));
                        }
                    }
                }
            }
        }
        Ok(())
    }

    fn ensure_trailing_newline(&mut self) {
        let len = self.lines.len();
        self.ensure_newline_before(len);
    }

    fn ensure_newline_before(&mut self, index: usize) {
        if index == 0 {
            return;
        }
        let previous = &mut self.lines[index - 1];
        if content_and_ending(&previous.raw).1.is_empty() {
            previous.raw.push_str(&self.preferred_newline);
            if let Some(pair) = &mut previous.pair {
                pair.suffix.push_str(&self.preferred_newline);
            }
        }
    }
}

fn split_lines(source: &str) -> Vec<String> {
    if source.is_empty() {
        return Vec::new();
    }
    source.split_inclusive('\n').map(str::to_owned).collect()
}

fn content_and_ending(raw: &str) -> (&str, &str) {
    if let Some(content) = raw.strip_suffix("\r\n") {
        (content, "\r\n")
    } else if let Some(content) = raw.strip_suffix('\n') {
        (content, "\n")
    } else {
        (raw, "")
    }
}

fn parse_pair(
    format: LineFormat,
    raw: &str,
    section: Option<&str>,
    first_line: bool,
) -> Result<Option<Pair>> {
    let (content, _) = content_and_ending(raw);
    let syntax = if first_line {
        content.strip_prefix('\u{feff}').unwrap_or(content)
    } else {
        content
    };
    let syntax_offset = content.len() - syntax.len();
    let trimmed = syntax.trim_start();
    if trimmed.is_empty()
        || trimmed.starts_with('#')
        || trimmed.starts_with(';')
        || (format == LineFormat::Ini && trimmed.starts_with('['))
    {
        return Ok(None);
    }
    let delimiter = syntax
        .char_indices()
        .find(|(_, character)| matches!(character, '=' | ':'))
        .map(|(index, _)| syntax_offset + index);
    let Some(delimiter) = delimiter else {
        return Ok(None);
    };
    let key = content[..delimiter].trim();
    if key.is_empty() {
        bail!("line setting contains an empty key");
    }
    let mut value_start = delimiter + 1;
    while content
        .as_bytes()
        .get(value_start)
        .is_some_and(u8::is_ascii_whitespace)
    {
        value_start += 1;
    }
    let (value, value_end, quote) = parse_line_value(content, value_start)?;
    let path = match format {
        LineFormat::Ini => match section {
            Some(section) => format!(
                "/sections/{}/{}",
                escape_pointer(section),
                escape_pointer(key)
            ),
            None => format!("/global/{}", escape_pointer(key)),
        },
        LineFormat::KeyValue => format!("/values/{}", escape_pointer(key)),
    };
    Ok(Some(Pair {
        path,
        prefix: raw[..value_start].to_owned(),
        suffix: raw[value_end..].to_owned(),
        value,
        quote,
    }))
}

fn parse_section_header(content: &str) -> Result<Option<String>> {
    let trimmed = content.trim_start();
    if !trimmed.starts_with('[') {
        return Ok(None);
    }
    let end = trimmed
        .find(']')
        .ok_or_else(|| anyhow!("unterminated INI section header"))?;
    let name = trimmed[1..end].trim();
    if name.is_empty() {
        bail!("INI section name cannot be empty");
    }
    let remainder = trimmed[end + 1..].trim_start();
    if !remainder.is_empty() && !remainder.starts_with(';') && !remainder.starts_with('#') {
        bail!("ambiguous content after INI section header");
    }
    Ok(Some(name.to_owned()))
}

fn has_unescaped_continuation(content: &str) -> bool {
    let count = content
        .trim_end()
        .as_bytes()
        .iter()
        .rev()
        .take_while(|byte| **byte == b'\\')
        .count();
    count % 2 == 1
}

fn parse_line_value(content: &str, start: usize) -> Result<(String, usize, Option<char>)> {
    let Some(first) = content[start..].chars().next() else {
        return Ok((String::new(), start, None));
    };
    if matches!(first, '\'' | '"') {
        let inner_start = start + first.len_utf8();
        let mut escaped = false;
        for (offset, character) in content[inner_start..].char_indices() {
            if escaped {
                escaped = false;
                continue;
            }
            if character == '\\' {
                escaped = true;
                continue;
            }
            if character == first {
                let close = inner_start + offset;
                let end = close + character.len_utf8();
                let remainder = content[end..].trim_start();
                if !remainder.is_empty()
                    && !remainder.starts_with(';')
                    && !remainder.starts_with('#')
                {
                    bail!("ambiguous content after quoted line-setting value");
                }
                return Ok((
                    decode_quoted_value(&content[inner_start..close], first)?,
                    end,
                    Some(first),
                ));
            }
        }
        bail!("unterminated quoted line-setting value");
    }

    let mut comment = None;
    for (offset, character) in content[start..].char_indices() {
        if matches!(character, ';' | '#')
            && offset > 0
            && content.as_bytes()[start + offset - 1].is_ascii_whitespace()
        {
            comment = Some(start + offset);
            break;
        }
    }
    let mut end = comment.unwrap_or(content.len());
    while end > start && content.as_bytes()[end - 1].is_ascii_whitespace() {
        end -= 1;
    }
    Ok((content[start..end].to_owned(), end, None))
}

fn decode_quoted_value(value: &str, quote: char) -> Result<String> {
    let mut decoded = String::new();
    let mut chars = value.chars();
    while let Some(character) = chars.next() {
        if character != '\\' {
            decoded.push(character);
            continue;
        }
        match chars.next() {
            Some(next) if next == quote || next == '\\' => decoded.push(next),
            Some(_) => bail!("unsupported escape in quoted line-setting value"),
            None => bail!("unterminated escape in quoted line-setting value"),
        }
    }
    Ok(decoded)
}

fn encode_line_value(value: &str, quote: Option<char>) -> String {
    let Some(quote) = quote else {
        return value.to_owned();
    };
    let escaped = value
        .replace('\\', "\\\\")
        .replace(quote, &format!("\\{quote}"));
    format!("{quote}{escaped}{quote}")
}

fn new_pair_line(path: &str, key: &str, value: &str, newline: &str) -> Line {
    let prefix = format!("{key}=");
    let suffix = newline.to_owned();
    Line {
        raw: format!("{prefix}{value}{suffix}"),
        pair: Some(Pair {
            path: path.to_owned(),
            prefix,
            suffix,
            value: value.to_owned(),
            quote: None,
        }),
        section_header: None,
    }
}

enum IniLocation {
    Global(String),
    Section { section: String, key: String },
}

fn ini_location(path: &str) -> Result<IniLocation> {
    let parts = pointer_parts(path)?;
    match parts.as_slice() {
        [scope, key] if scope == "global" => Ok(IniLocation::Global(key.clone())),
        [scope, section, key] if scope == "sections" => Ok(IniLocation::Section {
            section: section.clone(),
            key: key.clone(),
        }),
        _ => {
            bail!("INI allowlisted path {path} must be /global/<key> or /sections/<section>/<key>")
        }
    }
}

fn key_value_key(path: &str) -> Result<String> {
    let parts = pointer_parts(path)?;
    if let [scope, key] = parts.as_slice() {
        if scope == "values" {
            return Ok(key.clone());
        }
    }
    bail!("key-value allowlisted path {path} must be /values/<key>")
}

fn pointer_parts(path: &str) -> Result<Vec<String>> {
    if !path.starts_with('/') {
        bail!("invalid JSON pointer {path}");
    }
    path.split('/').skip(1).map(unescape_pointer).collect()
}

fn set_string_pointer(target: &mut Value, path: &str, value: String) -> Result<()> {
    let parts = pointer_parts(path)?;
    let (last, parents) = parts
        .split_last()
        .ok_or_else(|| anyhow!("cannot assign the JSON-pointer root"))?;
    let mut current = target;
    for part in parents {
        let map = current
            .as_object_mut()
            .ok_or_else(|| anyhow!("line model path crosses a scalar value"))?;
        current = map
            .entry(part.clone())
            .or_insert_with(|| Value::Object(Map::new()));
    }
    current
        .as_object_mut()
        .ok_or_else(|| anyhow!("line model parent is not an object"))?
        .insert(last.clone(), Value::String(value));
    Ok(())
}

fn escape_pointer(value: &str) -> String {
    value.replace('~', "~0").replace('/', "~1")
}

fn unescape_pointer(value: &str) -> Result<String> {
    let mut decoded = String::new();
    let mut chars = value.chars();
    while let Some(character) = chars.next() {
        if character != '~' {
            decoded.push(character);
            continue;
        }
        match chars.next() {
            Some('0') => decoded.push('~'),
            Some('1') => decoded.push('/'),
            _ => bail!("invalid JSON-pointer escape in {value}"),
        }
    }
    Ok(decoded)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn ini_noop_round_trip_is_byte_exact_and_patch_preserves_unknown_lines() {
        let input = b"; comment\r\nglobal = keep\r\n\r\n[General]\r\ntheme = dark  \r\nplugin.option=yes\r\n";
        let mut document = LineDocument::parse(LineFormat::Ini, input).unwrap();
        assert_eq!(document.render(), input);
        let allowlist = vec!["/sections/General/theme".to_owned()];
        assert_eq!(
            document.project(&allowlist).unwrap(),
            json!({"sections":{"General":{"theme":"dark"}}})
        );
        document
            .patch(
                &json!({"sections":{"General":{"theme":"light"}}}),
                &allowlist,
            )
            .unwrap();
        assert_eq!(
            String::from_utf8(document.render()).unwrap(),
            "; comment\r\nglobal = keep\r\n\r\n[General]\r\ntheme = light  \r\nplugin.option=yes\r\n"
        );
    }

    #[test]
    fn key_value_supports_vlc_and_wireshark_delimiters() {
        let input = include_bytes!("../../fixtures/adapters/vlc-vlcrc");
        let mut document = LineDocument::parse(LineFormat::KeyValue, input).unwrap();
        let allowlist = vec![
            "/values/qt-privacy-ask".to_owned(),
            "/values/qt-updates-notif".to_owned(),
        ];
        document
            .patch(
                &json!({"values":{"qt-privacy-ask":"1","qt-updates-notif":"0"}}),
                &allowlist,
            )
            .unwrap();
        let rendered = String::from_utf8(document.render()).unwrap();
        assert!(rendered.contains("qt-privacy-ask=1"));
        assert!(rendered.contains("qt-updates-notif: 0"));
        assert!(rendered.contains("http-password=fixture-secret-must-not-be-exported"));
    }

    #[test]
    fn line_codec_refuses_duplicates_non_strings_and_outside_paths() {
        assert!(LineDocument::parse(LineFormat::KeyValue, b"a=1\na=2\n").is_err());
        let mut document = LineDocument::parse(LineFormat::KeyValue, b"a=1\n").unwrap();
        let allowlist = vec!["/values/a".to_owned()];
        assert!(document
            .patch(&json!({"values":{"a":1}}), &allowlist)
            .is_err());
        assert!(document
            .patch(&json!({"values":{"b":"2"}}), &allowlist)
            .is_err());
    }

    #[test]
    fn missing_ini_keys_are_inserted_in_the_correct_section() {
        let mut document = LineDocument::parse(LineFormat::Ini, b"[One]\na=1\n[Two]\nb=2").unwrap();
        let allowlist = vec!["/sections/One/new".to_owned()];
        document
            .patch(&json!({"sections":{"One":{"new":"value"}}}), &allowlist)
            .unwrap();
        assert_eq!(
            String::from_utf8(document.render()).unwrap(),
            "[One]\na=1\nnew=value\n[Two]\nb=2"
        );
    }

    #[test]
    fn ini_handles_bom_comments_quotes_and_mixed_newlines_without_losing_bytes() {
        let input = "\u{feff}[General] ; retained\r\ntheme = \"dark;mode\" # retained\npath='a\\\\b' ; retained\r\n";
        let mut document = LineDocument::parse(LineFormat::Ini, input.as_bytes()).unwrap();
        assert_eq!(document.render(), input.as_bytes());
        let allowlist = vec![
            "/sections/General/theme".to_owned(),
            "/sections/General/path".to_owned(),
        ];
        assert_eq!(
            document.project(&allowlist).unwrap(),
            json!({"sections":{"General":{"theme":"dark;mode","path":"a\\b"}}})
        );
        document
            .patch(
                &json!({"sections":{"General":{"theme":"light","path":"c\\d"}}}),
                &allowlist,
            )
            .unwrap();
        assert_eq!(
            String::from_utf8(document.render()).unwrap(),
            "\u{feff}[General] ; retained\r\ntheme = \"light\" # retained\npath='c\\\\d' ; retained\r\n"
        );
    }

    #[test]
    fn ini_rejects_ambiguous_continuations_and_trailing_section_content() {
        assert!(LineDocument::parse(LineFormat::Ini, b"value=one\\\n two\n").is_err());
        assert!(
            LineDocument::parse(LineFormat::Ini, b"[General] unexpected\nvalue=one\n").is_err()
        );
        assert!(LineDocument::parse(LineFormat::Ini, b"value=\"unterminated\n").is_err());
    }
}
