use anyhow::{bail, Result};

/// Extract one unambiguous dotted version token and return its major component.
///
/// Standalone numbers are deliberately ignored so product names such as
/// `1Password` and build counters cannot be mistaken for the application
/// version. The complete output must contain exactly one candidate so a later
/// diagnostic line cannot conflict with the selected application version.
pub fn parse_major(output: &str) -> Result<u64> {
    let candidates = output
        .split_ascii_whitespace()
        .filter_map(version_token)
        .collect::<Vec<_>>();
    let token = match candidates.as_slice() {
        [token] => *token,
        [] => bail!("version command did not return one dotted version token"),
        _ => bail!("version command returned multiple dotted version tokens"),
    };
    token
        .split('.')
        .next()
        .expect("validated version token has a major")
        .parse()
        .map_err(|_| anyhow::anyhow!("application major version is out of range"))
}

fn version_token(raw: &str) -> Option<&str> {
    let trimmed = raw.trim_matches(|character: char| {
        matches!(
            character,
            '(' | ')' | '[' | ']' | '{' | '}' | ',' | ';' | ':'
        )
    });
    let token = trimmed
        .strip_prefix('v')
        .or_else(|| trimmed.strip_prefix('V'))
        .unwrap_or(trimmed);
    let core = token
        .split_once(['-', '+'])
        .map(|(value, _)| value)
        .unwrap_or(token);
    let mut components = core.split('.');
    let major = components.next()?;
    let minor = components.next()?;
    if major.is_empty()
        || minor.is_empty()
        || !major.bytes().all(|byte| byte.is_ascii_digit())
        || !minor.bytes().all(|byte| byte.is_ascii_digit())
        || components.any(|component| {
            component.is_empty() || !component.bytes().all(|byte| byte.is_ascii_digit())
        })
    {
        return None;
    }
    Some(core)
}

pub fn require_supported_major(output: &str, supported: &[u64]) -> Result<u64> {
    if supported.is_empty() {
        bail!("supported major-version list cannot be empty");
    }
    let major = parse_major(output)?;
    if supported.contains(&major) {
        Ok(major)
    } else {
        bail!(
            "unsupported application major version {major}; supported majors: {}",
            supported
                .iter()
                .map(u64::to_string)
                .collect::<Vec<_>>()
                .join(", ")
        )
    }
}

pub fn require_supported(
    output: &str,
    supported_exact: &[String],
    supported_majors: &[u64],
) -> Result<()> {
    match (supported_exact.is_empty(), supported_majors.is_empty()) {
        (false, true) => {
            let version = output.trim();
            if supported_exact.iter().any(|supported| supported == version) {
                Ok(())
            } else {
                bail!(
                    "unsupported exact application version {version:?}; supported versions: {}",
                    supported_exact.join(", ")
                )
            }
        }
        (true, false) => require_supported_major(output, supported_majors).map(|_| ()),
        (true, true) => bail!("an exact or major application-version gate is required"),
        (false, false) => bail!("exact and major application-version gates are mutually exclusive"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_common_version_output_and_refuses_unknown_majors() {
        assert_eq!(parse_major("OBS Studio 31.0.1\n").unwrap(), 31);
        assert_eq!(parse_major("v4.38.0 (build 123)").unwrap(), 4);
        assert_eq!(parse_major("1Password CLI 2.31.0").unwrap(), 2);
        assert!(parse_major("1.102.3\n  long version: 1.102.3-t123").is_err());
        assert!(parse_major("App 1.0.0\nApp 2.0.0").is_err());
        assert_eq!(
            require_supported_major("FreeCAD 1.0.0", &[1, 2]).unwrap(),
            1
        );
        assert!(require_supported_major("FreeCAD 3.0.0", &[1, 2])
            .unwrap_err()
            .to_string()
            .contains("unsupported application major version 3"));
        assert!(parse_major("unknown").is_err());
        assert!(parse_major("build 123").is_err());
        assert!(parse_major("App 2.3.0 runtime 1.9.0").is_err());
    }

    #[test]
    fn exact_versions_match_the_complete_trimmed_output() {
        let exact = vec!["2.2.1-beta.2".to_owned()];
        require_supported("2.2.1-beta.2\n", &exact, &[]).unwrap();
        assert!(require_supported("2.2.1", &exact, &[])
            .unwrap_err()
            .to_string()
            .contains("unsupported exact application version"));
        assert!(require_supported("2.2.1-beta.2", &exact, &[2]).is_err());
    }
}
