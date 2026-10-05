use crate::model::{Host, ValueType};
use anyhow::{anyhow, Context, Result};
use serde_json::Value;
use std::collections::BTreeMap;
use std::io::Write;
use std::process::Command;
use std::process::Stdio;

pub trait PrefStore {
    fn read(&self, domain: &str, key: &str, host: Host) -> Result<Option<Value>>;
    fn write(&mut self, domain: &str, key: &str, val: &Value, host: Host) -> Result<()>;
    fn write_typed(
        &mut self,
        domain: &str,
        key: &str,
        val: &Value,
        host: Host,
        _ty: ValueType,
    ) -> Result<()> {
        self.write(domain, key, val, host)
    }
    fn is_forced(&self, domain: &str, key: &str) -> Result<bool>;
    fn list_keys(&self, domain: &str, host: Host) -> Result<Vec<String>>;
    fn synchronize(&mut self, domain: &str) -> Result<()>;
}

#[derive(Default)]
pub struct FakePrefStore {
    pub values: BTreeMap<(String, Host, String), Value>,
    pub forced: BTreeMap<(String, String), bool>,
    pub synchronized: Vec<String>,
}

impl FakePrefStore {
    pub fn set(&mut self, domain: &str, key: &str, host: Host, value: Value) {
        self.values.insert((domain.into(), host, key.into()), value);
    }
}

impl PrefStore for FakePrefStore {
    fn read(&self, domain: &str, key: &str, host: Host) -> Result<Option<Value>> {
        Ok(self.values.get(&(domain.into(), host, key.into())).cloned())
    }
    fn write(&mut self, domain: &str, key: &str, val: &Value, host: Host) -> Result<()> {
        self.set(domain, key, host, val.clone());
        Ok(())
    }
    fn is_forced(&self, domain: &str, key: &str) -> Result<bool> {
        Ok(*self
            .forced
            .get(&(domain.into(), key.into()))
            .unwrap_or(&false))
    }
    fn list_keys(&self, domain: &str, host: Host) -> Result<Vec<String>> {
        Ok(self
            .values
            .keys()
            .filter(|(d, h, _)| d == domain && *h == host)
            .map(|(_, _, k)| k.clone())
            .collect())
    }
    fn synchronize(&mut self, domain: &str) -> Result<()> {
        self.synchronized.push(domain.into());
        Ok(())
    }
}

pub struct DefaultsCliStore;
impl PrefStore for DefaultsCliStore {
    fn read(&self, domain: &str, key: &str, host: Host) -> Result<Option<Value>> {
        let mut command = Command::new("defaults");
        if host == Host::Current {
            command.arg("-currentHost");
        }
        let output = command
            .args(["export", domain, "-"])
            .output()
            .context("run defaults export")?;
        if !output.status.success() {
            return Ok(None);
        }
        let plist = plist::Value::from_reader_xml(output.stdout.as_slice())
            .context("parse defaults plist")?;
        Ok(plist
            .as_dictionary()
            .and_then(|d| d.get(key))
            .map(plist_to_json))
    }
    fn write(&mut self, domain: &str, key: &str, val: &Value, host: Host) -> Result<()> {
        let value_type = match val {
            Value::Bool(_) => ValueType::Bool,
            Value::Number(number) if number.as_i64().is_some() || number.as_u64().is_some() => {
                ValueType::Int
            }
            Value::Number(_) => ValueType::Float,
            Value::String(_) => ValueType::String,
            Value::Array(_) => ValueType::Array,
            Value::Object(_) => ValueType::Dict,
            Value::Null => return Err(anyhow!("null is not a CFPreferences value")),
        };
        self.write_typed(domain, key, val, host, value_type)
    }
    fn write_typed(
        &mut self,
        domain: &str,
        key: &str,
        val: &Value,
        host: Host,
        ty: ValueType,
    ) -> Result<()> {
        // `defaults write` cannot faithfully express nested typed collections.
        // The fallback therefore exports, updates, and imports the domain plist.
        // CFPreferences remains the normal macOS backend.
        let mut export = Command::new("defaults");
        if host == Host::Current {
            export.arg("-currentHost");
        }
        let output = export
            .args(["export", domain, "-"])
            .output()
            .context("run defaults export before write")?;
        let mut dictionary = if output.status.success() {
            plist::Value::from_reader_xml(output.stdout.as_slice())?
                .into_dictionary()
                .ok_or_else(|| anyhow!("defaults domain {domain} is not a dictionary"))?
        } else {
            plist::Dictionary::new()
        };
        dictionary.insert(key.to_owned(), json_to_plist_typed(val, ty)?);
        let mut xml = Vec::new();
        plist::to_writer_xml(&mut xml, &plist::Value::Dictionary(dictionary))?;

        let mut command = Command::new("defaults");
        if host == Host::Current {
            command.arg("-currentHost");
        }
        let mut child = command
            .args(["import", domain, "-"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .context("run defaults import")?;
        child
            .stdin
            .take()
            .ok_or_else(|| anyhow!("defaults import stdin unavailable"))?
            .write_all(&xml)?;
        let output = child.wait_with_output()?;
        if output.status.success() {
            Ok(())
        } else {
            Err(anyhow!(
                "defaults import failed: {}",
                String::from_utf8_lossy(&output.stderr)
            ))
        }
    }
    fn is_forced(&self, _domain: &str, _key: &str) -> Result<bool> {
        Ok(false)
    }
    fn list_keys(&self, domain: &str, host: Host) -> Result<Vec<String>> {
        let mut command = Command::new("defaults");
        if host == Host::Current {
            command.arg("-currentHost");
        }
        let output = command.args(["export", domain, "-"]).output()?;
        if !output.status.success() {
            return Ok(vec![]);
        }
        let plist = plist::Value::from_reader_xml(output.stdout.as_slice())?;
        Ok(plist
            .as_dictionary()
            .map(|d| d.keys().cloned().collect())
            .unwrap_or_default())
    }
    fn synchronize(&mut self, _domain: &str) -> Result<()> {
        Ok(())
    }
}

pub fn plist_to_json(value: &plist::Value) -> Value {
    match value {
        plist::Value::Boolean(v) => Value::Bool(*v),
        plist::Value::Integer(v) => v
            .as_signed()
            .map(Into::into)
            .or_else(|| v.as_unsigned().map(Into::into))
            .map(Value::Number)
            .unwrap_or(Value::Null),
        plist::Value::Real(v) => serde_json::Number::from_f64(*v)
            .map(Value::Number)
            .unwrap_or(Value::Null),
        plist::Value::String(v) => Value::String(v.clone()),
        plist::Value::Data(v) => Value::String(base64::Engine::encode(
            &base64::engine::general_purpose::STANDARD,
            v,
        )),
        plist::Value::Date(v) => Value::String(v.to_xml_format()),
        plist::Value::Array(v) => Value::Array(v.iter().map(plist_to_json).collect()),
        plist::Value::Dictionary(v) => Value::Object(
            v.iter()
                .map(|(k, v)| (k.clone(), plist_to_json(v)))
                .collect(),
        ),
        _ => Value::Null,
    }
}

pub fn json_to_plist(value: &Value) -> Result<plist::Value> {
    Ok(match value {
        Value::Null => return Err(anyhow!("null is not a CFPreferences value")),
        Value::Bool(v) => plist::Value::Boolean(*v),
        Value::Number(v) if v.as_i64().is_some() => {
            plist::Value::Integer(v.as_i64().unwrap().into())
        }
        Value::Number(v) if v.as_u64().is_some() => {
            plist::Value::Integer(v.as_u64().unwrap().into())
        }
        Value::Number(v) => plist::Value::Real(v.as_f64().ok_or_else(|| anyhow!("invalid float"))?),
        Value::String(v) => plist::Value::String(v.clone()),
        Value::Array(v) => plist::Value::Array(v.iter().map(json_to_plist).collect::<Result<_>>()?),
        Value::Object(v) => plist::Value::Dictionary(
            v.iter()
                .map(|(k, v)| Ok((k.clone(), json_to_plist(v)?)))
                .collect::<Result<_>>()?,
        ),
    })
}

fn json_to_plist_typed(value: &Value, ty: ValueType) -> Result<plist::Value> {
    match ty {
        ValueType::Data => Ok(plist::Value::Data(base64::Engine::decode(
            &base64::engine::general_purpose::STANDARD,
            value
                .as_str()
                .ok_or_else(|| anyhow!("data value must be a base64 string"))?,
        )?)),
        ValueType::Date => Ok(plist::Value::Date(plist::Date::from_xml_format(
            value
                .as_str()
                .ok_or_else(|| anyhow!("date value must be an RFC 3339 string"))?,
        )?)),
        _ => json_to_plist(value),
    }
}

#[cfg(target_os = "macos")]
mod cf {
    use super::*;
    use core_foundation::base::{CFRelease, TCFType};
    use core_foundation::data::CFData;
    use core_foundation::string::CFString;
    use std::ffi::c_void;
    use std::ptr;

    type CFStringRef = *const c_void;
    type CFDataRef = *const c_void;
    type CFPropertyListRef = *const c_void;
    #[link(name = "CoreFoundation", kind = "framework")]
    extern "C" {
        static kCFPreferencesCurrentUser: CFStringRef;
        static kCFPreferencesAnyHost: CFStringRef;
        static kCFPreferencesCurrentHost: CFStringRef;
        fn CFPreferencesCopyValue(
            key: CFStringRef,
            app: CFStringRef,
            user: CFStringRef,
            host: CFStringRef,
        ) -> CFPropertyListRef;
        fn CFPreferencesSetValue(
            key: CFStringRef,
            value: CFPropertyListRef,
            app: CFStringRef,
            user: CFStringRef,
            host: CFStringRef,
        );
        fn CFPreferencesSynchronize(app: CFStringRef, user: CFStringRef, host: CFStringRef)
            -> bool;
        fn CFPreferencesAppValueIsForced(key: CFStringRef, app: CFStringRef) -> bool;
        fn CFPreferencesCopyKeyList(
            app: CFStringRef,
            user: CFStringRef,
            host: CFStringRef,
        ) -> CFPropertyListRef;
        fn CFPropertyListCreateData(
            allocator: *const c_void,
            property: CFPropertyListRef,
            format: isize,
            options: usize,
            error: *mut *const c_void,
        ) -> CFDataRef;
        fn CFPropertyListCreateWithData(
            allocator: *const c_void,
            data: CFDataRef,
            options: usize,
            format: *mut isize,
            error: *mut *const c_void,
        ) -> CFPropertyListRef;
    }

    pub struct CfPrefStore;
    impl CfPrefStore {
        fn host(host: Host) -> CFStringRef {
            unsafe {
                if host == Host::Current {
                    kCFPreferencesCurrentHost
                } else {
                    kCFPreferencesAnyHost
                }
            }
        }
        unsafe fn cf_to_json(value: CFPropertyListRef) -> Result<Value> {
            let data = CFPropertyListCreateData(ptr::null(), value, 100, 0, ptr::null_mut());
            if data.is_null() {
                return Err(anyhow!("CFPropertyListCreateData failed"));
            }
            let wrapped = CFData::wrap_under_create_rule(data as _);
            let plist = plist::Value::from_reader_xml(wrapped.bytes())?;
            Ok(plist_to_json(&plist))
        }
        unsafe fn json_to_cf(value: &Value) -> Result<CFPropertyListRef> {
            let plist = json_to_plist(value)?;
            let mut xml = Vec::new();
            plist::to_writer_xml(&mut xml, &plist)?;
            let data = CFData::from_buffer(&xml);
            let result = CFPropertyListCreateWithData(
                ptr::null(),
                data.as_concrete_TypeRef() as _,
                0,
                ptr::null_mut(),
                ptr::null_mut(),
            );
            if result.is_null() {
                Err(anyhow!("CFPropertyListCreateWithData failed"))
            } else {
                Ok(result)
            }
        }
        unsafe fn json_to_cf_typed(value: &Value, ty: ValueType) -> Result<CFPropertyListRef> {
            let plist = json_to_plist_typed(value, ty)?;
            let mut xml = Vec::new();
            plist::to_writer_xml(&mut xml, &plist)?;
            let data = CFData::from_buffer(&xml);
            let result = CFPropertyListCreateWithData(
                ptr::null(),
                data.as_concrete_TypeRef() as _,
                0,
                ptr::null_mut(),
                ptr::null_mut(),
            );
            if result.is_null() {
                Err(anyhow!("CFPropertyListCreateWithData failed"))
            } else {
                Ok(result)
            }
        }
    }
    impl PrefStore for CfPrefStore {
        fn read(&self, domain: &str, key: &str, host: Host) -> Result<Option<Value>> {
            unsafe {
                let app = CFString::new(domain);
                let key = CFString::new(key);
                let raw = CFPreferencesCopyValue(
                    key.as_concrete_TypeRef() as _,
                    app.as_concrete_TypeRef() as _,
                    kCFPreferencesCurrentUser,
                    Self::host(host),
                );
                if raw.is_null() {
                    Ok(None)
                } else {
                    let result = Self::cf_to_json(raw);
                    CFRelease(raw);
                    result.map(Some)
                }
            }
        }
        fn write(&mut self, domain: &str, key: &str, val: &Value, host: Host) -> Result<()> {
            unsafe {
                let app = CFString::new(domain);
                let key = CFString::new(key);
                let raw = Self::json_to_cf(val)?;
                CFPreferencesSetValue(
                    key.as_concrete_TypeRef() as _,
                    raw,
                    app.as_concrete_TypeRef() as _,
                    kCFPreferencesCurrentUser,
                    Self::host(host),
                );
                CFRelease(raw);
                Ok(())
            }
        }
        fn write_typed(
            &mut self,
            domain: &str,
            key_name: &str,
            val: &Value,
            host: Host,
            ty: ValueType,
        ) -> Result<()> {
            unsafe {
                let app = CFString::new(domain);
                let key = CFString::new(key_name);
                let raw = Self::json_to_cf_typed(val, ty)?;
                CFPreferencesSetValue(
                    key.as_concrete_TypeRef() as _,
                    raw,
                    app.as_concrete_TypeRef() as _,
                    kCFPreferencesCurrentUser,
                    Self::host(host),
                );
                CFRelease(raw);
                Ok(())
            }
        }
        fn is_forced(&self, domain: &str, key: &str) -> Result<bool> {
            unsafe {
                let app = CFString::new(domain);
                let key = CFString::new(key);
                Ok(CFPreferencesAppValueIsForced(
                    key.as_concrete_TypeRef() as _,
                    app.as_concrete_TypeRef() as _,
                ))
            }
        }
        fn list_keys(&self, domain: &str, host: Host) -> Result<Vec<String>> {
            unsafe {
                let app = CFString::new(domain);
                let raw = CFPreferencesCopyKeyList(
                    app.as_concrete_TypeRef() as _,
                    kCFPreferencesCurrentUser,
                    Self::host(host),
                );
                if raw.is_null() {
                    return Ok(vec![]);
                }
                let value = Self::cf_to_json(raw);
                CFRelease(raw);
                Ok(value?
                    .as_array()
                    .map(|v| {
                        v.iter()
                            .filter_map(|x| x.as_str().map(str::to_owned))
                            .collect()
                    })
                    .unwrap_or_default())
            }
        }
        fn synchronize(&mut self, domain: &str) -> Result<()> {
            unsafe {
                let app = CFString::new(domain);
                let any = CFPreferencesSynchronize(
                    app.as_concrete_TypeRef() as _,
                    kCFPreferencesCurrentUser,
                    kCFPreferencesAnyHost,
                );
                let current = CFPreferencesSynchronize(
                    app.as_concrete_TypeRef() as _,
                    kCFPreferencesCurrentUser,
                    kCFPreferencesCurrentHost,
                );
                if any && current {
                    Ok(())
                } else {
                    Err(anyhow!("CFPreferences synchronize failed for {domain}"))
                }
            }
        }
    }
}

#[cfg(target_os = "macos")]
pub use cf::CfPrefStore;
