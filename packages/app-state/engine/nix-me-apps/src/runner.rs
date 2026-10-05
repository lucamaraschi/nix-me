use anyhow::{anyhow, Result};
use std::process::Command;

#[derive(Debug)]
pub struct CommandExecutionError(pub String);

impl std::fmt::Display for CommandExecutionError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(&self.0)
    }
}

impl std::error::Error for CommandExecutionError {}

pub trait CommandRunner {
    fn run(&mut self, command: &str) -> Result<String>;
    fn succeeds(&mut self, command: &str) -> bool {
        self.run(command).is_ok()
    }
}

#[derive(Default)]
pub struct RealCommandRunner {
    pub no_exec: bool,
    pub recorded: Vec<String>,
}

impl CommandRunner for RealCommandRunner {
    fn run(&mut self, command: &str) -> Result<String> {
        self.recorded.push(command.to_string());
        if self.no_exec {
            return Ok(String::new());
        }
        let output = Command::new("/bin/sh")
            .args(["-c", command])
            .output()
            .map_err(|error| {
                CommandExecutionError(format!("execute command {command}: {error}"))
            })?;
        if !output.status.success() {
            return Err(CommandExecutionError(format!(
                "command failed ({}): {}",
                output.status,
                String::from_utf8_lossy(&output.stderr).trim()
            ))
            .into());
        }
        Ok(String::from_utf8_lossy(&output.stdout).into_owned())
    }
}

#[derive(Default)]
pub struct ReplayCommandRunner {
    pub outputs: std::collections::BTreeMap<String, Result<String, String>>,
    pub recorded: Vec<String>,
}

impl CommandRunner for ReplayCommandRunner {
    fn run(&mut self, command: &str) -> Result<String> {
        self.recorded.push(command.into());
        match self.outputs.get(command) {
            Some(Ok(value)) => Ok(value.clone()),
            Some(Err(error)) => Err(anyhow!(error.clone())),
            None => Err(anyhow!("no replay transcript for command: {command}")),
        }
    }
}

pub trait Clock {
    fn now(&self) -> String;
}
pub struct SystemClock;
impl Clock for SystemClock {
    fn now(&self) -> String {
        std::process::Command::new("date")
            .args(["-u", "+%Y-%m-%dT%H:%M:%SZ"])
            .output()
            .ok()
            .filter(|o| o.status.success())
            .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_owned())
            .unwrap_or_else(|| "1970-01-01T00:00:00Z".into())
    }
}
pub struct FixedClock(pub String);
impl Clock for FixedClock {
    fn now(&self) -> String {
        self.0.clone()
    }
}
