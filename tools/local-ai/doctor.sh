#!/usr/bin/env bash
set -u

ds4_dir="${DS4_RUNTIME_DIR:-$HOME/src/ai/ds4}"
pi_ds4_dir="${PI_DS4_DIR:-$HOME/src/ai/pi-ds4}"
pi_agent_dir="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
failures=0
warnings=0

pass() {
  printf 'PASS  %s\n' "$1"
}

warn() {
  printf 'WARN  %s\n' "$1"
  warnings=$((warnings + 1))
}

fail() {
  printf 'FAIL  %s\n' "$1"
  failures=$((failures + 1))
}

if [[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]]; then
  pass "Apple Silicon Mac detected"
else
  fail "DS4 requires an Apple Silicon Mac"
fi

if xcode-select -p >/dev/null 2>&1; then
  pass "Xcode Command Line Tools are installed"
else
  fail "Xcode Command Line Tools are missing; run: xcode-select --install"
fi

if command -v pi >/dev/null 2>&1; then
  pass "Pi is available at $(command -v pi)"
else
  fail "Pi is not installed; apply the local-ai profile"
fi

if [[ -f "$ds4_dir/Makefile" ]]; then
  pass "DS4 checkout exists at $ds4_dir"
else
  fail "DS4 checkout is missing at $ds4_dir"
fi

if [[ -f "$pi_ds4_dir/install-pi-extension-local.sh" ]]; then
  pass "pi-ds4 checkout exists at $pi_ds4_dir"
else
  fail "pi-ds4 checkout is missing at $pi_ds4_dir"
fi

if [[ -x "$ds4_dir/ds4-server" ]]; then
  pass "DS4 server is built"
else
  warn "DS4 server is not built; run: local-ai-setup"
fi

if [[ -L "$pi_agent_dir/extensions/pi-ds4" && -e "$pi_agent_dir/extensions/pi-ds4" ]]; then
  pass "Pi DS4 extension is linked"
else
  warn "Pi DS4 extension is not linked; run: local-ai-setup"
fi

support_link="$HOME/.pi/ds4/support"
if [[ -L "$support_link" && -e "$support_link" ]] &&
  [[ "$(cd "$support_link" && pwd -P)" == "$(cd "$ds4_dir" 2>/dev/null && pwd -P)" ]]; then
  pass "Pi DS4 runtime points to $ds4_dir"
else
  warn "Pi DS4 runtime does not point to $ds4_dir; run: local-ai-setup"
fi

settings_file="$HOME/.pi/ds4/settings.json"
if [[ -f "$settings_file" ]] && jq -e --arg runtime "$ds4_dir" '
  .protocol == "openai-responses" and .runtimeDir == $runtime
' "$settings_file" >/dev/null 2>&1; then
  pass "Pi DS4 settings are valid"
else
  warn "Pi DS4 settings are missing or do not match the configured runtime"
fi

shopt -s nullglob
model_files=("$ds4_dir"/gguf/*ds4*)
if [[ -e "$ds4_dir/ds4flash.gguf" ]] || ((${#model_files[@]} > 0)); then
  pass "A DS4 model is present"
else
  warn "DeepSeek V4 Flash Q2 is not present; run: local-ai-setup --download-model"
fi

if [[ "$(uname -s)" == "Darwin" ]]; then
  ram_bytes="$(/usr/sbin/sysctl -n hw.memsize 2>/dev/null || printf '0')"
  ram_gib=$((ram_bytes / 1073741824))
  if ((ram_gib >= 96)); then
    pass "Memory is ${ram_gib} GiB (96 GiB or more recommended)"
  else
    warn "Memory is ${ram_gib} GiB; DeepSeek V4 Flash Q2 recommends about 96 GiB"
  fi
fi

free_kib="$(df -Pk "$HOME" 2>/dev/null | awk 'NR == 2 { print $4 }')"
if [[ ! "$free_kib" =~ ^[0-9]+$ ]]; then
  free_kib=0
fi
free_gib=$((free_kib / 1048576))
if ((free_gib >= 100)); then
  pass "Home volume has ${free_gib} GiB free"
else
  warn "Home volume has ${free_gib} GiB free; reserve at least 100 GiB for the model and build"
fi

printf '\n%d failure(s), %d warning(s)\n' "$failures" "$warnings"
if ((failures > 0)); then
  exit 1
fi
