use std::collections::BTreeMap;
use std::io::Cursor;

use anyhow::{anyhow, bail, Context, Result};
use quick_xml::events::{BytesStart, Event};
use quick_xml::{Reader, Writer};
use serde_json::{Map, Number, Value};

use crate::json::{assert_semantic_readback, merge_allowlisted, project_paths};

#[derive(Debug, Clone)]
pub struct QSettingsDocument {
    events: Vec<Event<'static>>,
    parameters: BTreeMap<String, Parameter>,
}

#[derive(Debug, Clone)]
struct Parameter {
    event_index: usize,
    kind: ParameterKind,
}

#[derive(Debug, Clone, Copy)]
enum ParameterKind {
    Text,
    Bool,
    Int,
    UInt,
    Float,
}

impl QSettingsDocument {
    pub fn parse(bytes: &[u8]) -> Result<Self> {
        let mut reader = Reader::from_reader(Cursor::new(bytes));
        reader.config_mut().trim_text(false);
        let mut buffer = Vec::new();
        let mut events = Vec::new();
        let mut groups = Vec::new();
        let mut parameters = BTreeMap::new();

        loop {
            let event = reader
                .read_event_into(&mut buffer)
                .context("parse QSettings XML")?;
            if matches!(event, Event::Eof) {
                break;
            }
            let owned = event.into_owned();
            let index = events.len();
            match &owned {
                Event::Start(start) if start.name().as_ref() == b"FCParamGroup" => {
                    groups.push(required_attribute(start, b"Name")?);
                }
                Event::End(end) if end.name().as_ref() == b"FCParamGroup" => {
                    groups
                        .pop()
                        .ok_or_else(|| anyhow!("QSettings XML closes an unopened group"))?;
                }
                Event::Empty(start) | Event::Start(start) => {
                    if let Some(kind) = parameter_kind(start.name().as_ref()) {
                        let name = required_attribute(start, b"Name")?;
                        let path = parameter_path(&groups, &name);
                        if parameters
                            .insert(
                                path.clone(),
                                Parameter {
                                    event_index: index,
                                    kind,
                                },
                            )
                            .is_some()
                        {
                            bail!("duplicate QSettings parameter path {path}");
                        }
                    }
                }
                _ => {}
            }
            events.push(owned);
            buffer.clear();
        }
        if !groups.is_empty() {
            bail!("QSettings XML contains an unclosed parameter group");
        }
        Ok(Self { events, parameters })
    }

    pub fn model(&self) -> Result<Value> {
        let mut root = Value::Object(Map::new());
        for (path, parameter) in &self.parameters {
            let event = self
                .events
                .get(parameter.event_index)
                .ok_or_else(|| anyhow!("QSettings parameter event is missing"))?;
            let start = event_start(event)?;
            let raw = required_attribute(start, b"Value")?;
            set_pointer(&mut root, path, parse_value(parameter.kind, &raw)?)?;
        }
        Ok(root)
    }

    pub fn project(&self, allowlist: &[String]) -> Result<Value> {
        project_paths(&self.model()?, allowlist)
    }

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
            let parameter = self
                .parameters
                .get(path)
                .ok_or_else(|| anyhow!("QSettings parameter {path} does not exist"))?;
            let value = after.ok_or_else(|| anyhow!("QSettings parameter {path} has no value"))?;
            let encoded = encode_value(parameter.kind, value)?;
            let event = self
                .events
                .get_mut(parameter.event_index)
                .ok_or_else(|| anyhow!("QSettings parameter event is missing"))?;
            replace_value_attribute(event, &encoded)?;
        }
        assert_semantic_readback(&self.model()?, desired, allowlist)
    }

    pub fn render(&self) -> Result<Vec<u8>> {
        let mut writer = Writer::new(Vec::new());
        for event in &self.events {
            writer.write_event(event.clone())?;
        }
        Ok(writer.into_inner())
    }
}

fn parameter_kind(name: &[u8]) -> Option<ParameterKind> {
    match name {
        b"FCText" => Some(ParameterKind::Text),
        b"FCBool" => Some(ParameterKind::Bool),
        b"FCInt" => Some(ParameterKind::Int),
        b"FCUInt" => Some(ParameterKind::UInt),
        b"FCFloat" => Some(ParameterKind::Float),
        _ => None,
    }
}

fn parameter_path(groups: &[String], name: &str) -> String {
    std::iter::once("groups")
        .chain(groups.iter().map(String::as_str))
        .chain(std::iter::once(name))
        .map(escape_pointer)
        .fold(String::new(), |mut path, segment| {
            path.push('/');
            path.push_str(&segment);
            path
        })
}

fn required_attribute(start: &BytesStart<'_>, name: &[u8]) -> Result<String> {
    for attribute in start.attributes().with_checks(false) {
        let attribute = attribute?;
        if attribute.key.as_ref() == name {
            return Ok(attribute.unescape_value()?.into_owned());
        }
    }
    bail!(
        "QSettings element {} is missing {}",
        String::from_utf8_lossy(start.name().as_ref()),
        String::from_utf8_lossy(name)
    )
}

fn parse_value(kind: ParameterKind, value: &str) -> Result<Value> {
    match kind {
        ParameterKind::Text => Ok(Value::String(value.to_owned())),
        ParameterKind::Bool => match value.to_ascii_lowercase().as_str() {
            "true" | "1" => Ok(Value::Bool(true)),
            "false" | "0" => Ok(Value::Bool(false)),
            _ => bail!("invalid QSettings boolean"),
        },
        ParameterKind::Int => Ok(Value::from(value.parse::<i64>()?)),
        ParameterKind::UInt => Ok(Value::from(value.parse::<u64>()?)),
        ParameterKind::Float => Ok(Value::Number(
            Number::from_f64(value.parse::<f64>()?)
                .ok_or_else(|| anyhow!("QSettings float is not finite"))?,
        )),
    }
}

fn encode_value(kind: ParameterKind, value: &Value) -> Result<String> {
    match (kind, value) {
        (ParameterKind::Text, Value::String(value)) => Ok(value.clone()),
        (ParameterKind::Bool, Value::Bool(value)) => Ok(if *value { "1" } else { "0" }.into()),
        (ParameterKind::Int, Value::Number(value)) if value.as_i64().is_some() => {
            Ok(value.as_i64().unwrap().to_string())
        }
        (ParameterKind::UInt, Value::Number(value)) if value.as_u64().is_some() => {
            Ok(value.as_u64().unwrap().to_string())
        }
        (ParameterKind::Float, Value::Number(value)) if value.as_f64().is_some() => {
            Ok(value.as_f64().unwrap().to_string())
        }
        _ => bail!("QSettings value has the wrong declared type"),
    }
}

fn event_start<'event, 'data>(event: &'event Event<'data>) -> Result<&'event BytesStart<'data>> {
    match event {
        Event::Empty(start) | Event::Start(start) => Ok(start),
        _ => bail!("QSettings parameter does not point to a start element"),
    }
}

fn replace_value_attribute(event: &mut Event<'static>, value: &str) -> Result<()> {
    let start = event_start(event)?;
    let name = String::from_utf8(start.name().as_ref().to_vec())?;
    let mut replacement = BytesStart::new(name);
    let mut replaced = false;
    let mut attributes = Vec::new();
    for attribute in start.attributes().with_checks(false) {
        let attribute = attribute?;
        let key = String::from_utf8(attribute.key.as_ref().to_vec())?;
        let old_value = attribute.unescape_value()?.into_owned();
        if key == "Value" {
            attributes.push((key, value.to_owned()));
            replaced = true;
        } else {
            attributes.push((key, old_value));
        }
    }
    if !replaced {
        attributes.push(("Value".into(), value.to_owned()));
    }
    for (key, value) in &attributes {
        replacement.push_attribute((key.as_str(), value.as_str()));
    }
    *event = match event {
        Event::Empty(_) => Event::Empty(replacement.into_owned()),
        Event::Start(_) => Event::Start(replacement.into_owned()),
        _ => unreachable!(),
    };
    Ok(())
}

fn set_pointer(target: &mut Value, path: &str, value: Value) -> Result<()> {
    let parts = path
        .split('/')
        .skip(1)
        .map(unescape_pointer)
        .collect::<Result<Vec<_>>>()?;
    let (last, parents) = parts
        .split_last()
        .ok_or_else(|| anyhow!("cannot assign QSettings root"))?;
    let mut current = target;
    for part in parents {
        current = current
            .as_object_mut()
            .ok_or_else(|| anyhow!("QSettings model path crosses a scalar"))?
            .entry(part.clone())
            .or_insert_with(|| Value::Object(Map::new()));
    }
    current
        .as_object_mut()
        .ok_or_else(|| anyhow!("QSettings model parent is not an object"))?
        .insert(last.clone(), value);
    Ok(())
}

fn escape_pointer(value: &str) -> String {
    value.replace('~', "~0").replace('/', "~1")
}

fn unescape_pointer(value: &str) -> Result<String> {
    let mut output = String::new();
    let mut chars = value.chars();
    while let Some(character) = chars.next() {
        if character != '~' {
            output.push(character);
            continue;
        }
        match chars.next() {
            Some('0') => output.push('~'),
            Some('1') => output.push('/'),
            _ => bail!("invalid JSON-pointer escape"),
        }
    }
    Ok(output)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    const FIXTURE: &[u8] = include_bytes!("../../fixtures/adapters/freecad-user.cfg");

    #[test]
    fn qsettings_projects_typed_values_and_preserves_unknown_xml() {
        let mut document = QSettingsDocument::parse(FIXTURE).unwrap();
        let paths = vec![
            "/groups/Root/BaseApp/Theme".to_owned(),
            "/groups/Root/BaseApp/CheckUpdates".to_owned(),
        ];
        assert_eq!(
            document.project(&paths).unwrap(),
            json!({"groups":{"Root":{"BaseApp":{"Theme":"dark","CheckUpdates":true}}}})
        );
        document
            .patch(
                &json!({"groups":{"Root":{"BaseApp":{"Theme":"light"}}}}),
                &paths,
            )
            .unwrap();
        let rendered = String::from_utf8(document.render().unwrap()).unwrap();
        assert!(rendered.contains("Name=\"Theme\" Value=\"light\""));
        assert!(rendered.contains("<Unknown Name=\"Opaque\" Value=\"leave\"/>"));
    }

    #[test]
    fn qsettings_noop_round_trip_is_exact_and_missing_paths_are_refused() {
        let mut document = QSettingsDocument::parse(FIXTURE).unwrap();
        assert_eq!(document.render().unwrap(), FIXTURE);
        let paths = vec!["/groups/Root/BaseApp/Missing".to_owned()];
        assert!(document
            .patch(
                &json!({"groups":{"Root":{"BaseApp":{"Missing":"value"}}}}),
                &paths,
            )
            .is_err());
    }
}
