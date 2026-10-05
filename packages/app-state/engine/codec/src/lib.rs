use std::collections::BTreeMap;
use std::sync::Arc;

use anyhow::{anyhow, Result};
use serde_json::Value;

/// Escape hatch for genuinely non-compositional app export formats.
/// Declarative pipelines should be preferred for registry recipes.
pub trait Codec: Send + Sync {
    fn id(&self) -> &str;
    fn version(&self) -> &str;
    fn encode(&self, model: &Value) -> Result<Vec<u8>>;
    fn decode(&self, artifact: &[u8]) -> Result<Value>;
    fn smoke(&self) -> Result<()>;
}

/// Compile-time codec registry used by the runtime escape hatch.
///
/// Codecs are deliberately linked into the single engine binary. This keeps the
/// distribution runtime-free and avoids loading untrusted dynamic libraries.
/// Adding a codec requires registering an implementation during construction;
/// the default registry is intentionally empty until a format cannot be
/// represented by the declarative pipeline primitives.
#[derive(Default)]
pub struct CodecRegistry {
    codecs: BTreeMap<(String, String), Arc<dyn Codec>>,
}

impl CodecRegistry {
    pub fn len(&self) -> usize {
        self.codecs.len()
    }

    pub fn is_empty(&self) -> bool {
        self.codecs.is_empty()
    }

    pub fn register<C: Codec + 'static>(&mut self, codec: C) -> Result<()> {
        let key = (codec.id().to_owned(), codec.version().to_owned());
        if self.codecs.contains_key(&key) {
            return Err(anyhow!("codec {}@{} is already registered", key.0, key.1));
        }
        self.codecs.insert(key, Arc::new(codec));
        Ok(())
    }

    pub fn resolve(&self, id: &str, version: &str) -> Result<Arc<dyn Codec>> {
        self.codecs
            .get(&(id.to_owned(), version.to_owned()))
            .cloned()
            .ok_or_else(|| anyhow!("compiled codec {id}@{version} is not installed"))
    }

    pub fn encode(&self, id: &str, version: &str, model: &Value) -> Result<Vec<u8>> {
        self.resolve(id, version)?.encode(model)
    }

    pub fn decode(&self, id: &str, version: &str, artifact: &[u8]) -> Result<Value> {
        self.resolve(id, version)?.decode(artifact)
    }

    pub fn smoke_all(&self) -> Result<()> {
        for codec in self.codecs.values() {
            codec.smoke()?;
        }
        Ok(())
    }
}

/// Registry linked into `nix-me-apps`. It is empty by design in v1.
pub fn builtin_registry() -> CodecRegistry {
    CodecRegistry::default()
}

#[cfg(test)]
mod tests {
    use super::*;

    struct JsonCodec;
    impl Codec for JsonCodec {
        fn id(&self) -> &str {
            "test-json"
        }
        fn version(&self) -> &str {
            "1"
        }
        fn encode(&self, model: &Value) -> Result<Vec<u8>> {
            Ok(serde_json::to_vec(model)?)
        }
        fn decode(&self, artifact: &[u8]) -> Result<Value> {
            Ok(serde_json::from_slice(artifact)?)
        }
        fn smoke(&self) -> Result<()> {
            let model = serde_json::json!({"codec": true});
            let bytes = self.encode(&model)?;
            if self.decode(&bytes)? != model {
                return Err(anyhow!("codec round trip changed the model"));
            }
            Ok(())
        }
    }

    #[test]
    fn registry_resolves_exact_versions_and_runs_smoke_tests() {
        let mut registry = CodecRegistry::default();
        registry.register(JsonCodec).unwrap();
        let model = serde_json::json!({"hello": "world"});
        let encoded = registry.encode("test-json", "1", &model).unwrap();
        assert_eq!(registry.decode("test-json", "1", &encoded).unwrap(), model);
        registry.smoke_all().unwrap();
        assert_eq!(registry.len(), 1);
        assert!(!registry.is_empty());
        assert!(registry.resolve("test-json", "2").is_err());
        assert!(registry.register(JsonCodec).is_err());
    }
}
