#!/usr/bin/env bash
set -euo pipefail

projects_json=""
flake_dir=""
hostname=""
home_dir="${HOME:-}"
git_timeout_seconds="${NIX_ME_PROJECT_GIT_TIMEOUT_SECONDS:-120}"

usage() {
  cat <<'EOF'
Usage:
  sync-projects.sh --projects-json '<json>' [--home /Users/name]
  sync-projects.sh --flake-dir /path/to/flake --hostname host [--home /Users/name]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --projects-json)
      projects_json="$2"
      shift 2
      ;;
    --flake-dir)
      flake_dir="$2"
      shift 2
      ;;
    --hostname)
      hostname="$2"
      shift 2
      ;;
    --home)
      home_dir="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$projects_json" ]]; then
  if [[ -z "$flake_dir" || -z "$hostname" ]]; then
    usage >&2
    exit 1
  fi

  projects_json="$(nix eval --json "${flake_dir}#darwinConfigurations.\"${hostname}\".config.projects.finalRepos")"
fi

if [[ -z "$home_dir" ]]; then
  echo "HOME is not set and no --home value was provided." >&2
  exit 1
fi

if [[ ! "$git_timeout_seconds" =~ ^[1-9][0-9]*$ ]]; then
  echo "NIX_ME_PROJECT_GIT_TIMEOUT_SECONDS must be a positive integer." >&2
  exit 1
fi

git_timeout_command="$(command -v timeout || command -v gtimeout || true)"

run_git() {
  if [[ -n "$git_timeout_command" ]]; then
    GIT_TERMINAL_PROMPT=0 "$git_timeout_command" --foreground "$git_timeout_seconds" git "$@"
  else
    GIT_TERMINAL_PROMPT=0 git "$@"
  fi
}

configure_ssh_agent() {
  local candidate
  local candidates=(
    "$home_dir/.1password/agent.sock"
    "$home_dir/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
  )

  if [[ -n "${SSH_AUTH_SOCK:-}" && -S "${SSH_AUTH_SOCK:-}" ]]; then
    return 0
  fi

  for candidate in "${candidates[@]}"; do
    if [[ -S "$candidate" ]]; then
      export SSH_AUTH_SOCK="$candidate"
      return 0
    fi
  done
}

configure_ssh_agent

if [[ "$(printf '%s' "$projects_json" | jq 'length')" -eq 0 ]]; then
  echo "==> No projects configured"
  exit 0
fi

resolve_path() {
  local raw_path="$1"

  case "$raw_path" in
    \~/*)
      printf '%s/%s\n' "$home_dir" "${raw_path#\~/}"
      ;;
    /*)
      printf '%s\n' "$raw_path"
      ;;
    *)
      printf '%s/%s\n' "$home_dir" "$raw_path"
      ;;
  esac
}

sync_project() {
  local project_json="$1"
  local name url path branch remote clone update abs_path parent_dir dirty current_branch current_url

  name="$(printf '%s' "$project_json" | jq -r '.name')"
  url="$(printf '%s' "$project_json" | jq -r '.url')"
  path="$(printf '%s' "$project_json" | jq -r '.path')"
  branch="$(printf '%s' "$project_json" | jq -r '.branch // empty')"
  remote="$(printf '%s' "$project_json" | jq -r '.remote // "origin"')"
  clone="$(printf '%s' "$project_json" | jq -r '.clone')"
  update="$(printf '%s' "$project_json" | jq -r '.update')"

  abs_path="$(resolve_path "$path")"
  parent_dir="$(dirname "$abs_path")"

  mkdir -p "$parent_dir"

  if [[ ! -e "$abs_path" ]]; then
    if [[ "$clone" != "true" ]]; then
      echo "==> [$name] Missing and clone disabled, skipping"
      return 0
    fi

    echo "==> [$name] Cloning into $abs_path"
    if [[ -n "$branch" ]]; then
      if ! run_git clone --branch "$branch" "$url" "$abs_path"; then
        echo "==> [$name] Clone failed; continuing with the remaining projects" >&2
        return 1
      fi
    else
      if ! run_git clone "$url" "$abs_path"; then
        echo "==> [$name] Clone failed; continuing with the remaining projects" >&2
        return 1
      fi
    fi
    return 0
  fi

  if [[ ! -d "$abs_path/.git" ]]; then
    echo "==> [$name] $abs_path exists but is not a git repository, skipping"
    return 0
  fi

  if git -C "$abs_path" remote get-url "$remote" >/dev/null 2>&1; then
    current_url="$(git -C "$abs_path" remote get-url "$remote")"
    if [[ "$current_url" != "$url" ]]; then
      echo "==> [$name] Updating $remote remote to $url"
      if ! git -C "$abs_path" remote set-url "$remote" "$url"; then
        echo "==> [$name] Could not update the $remote remote" >&2
        return 1
      fi
    fi
  else
    echo "==> [$name] Adding $remote remote"
    if ! git -C "$abs_path" remote add "$remote" "$url"; then
      echo "==> [$name] Could not add the $remote remote" >&2
      return 1
    fi
  fi

  echo "==> [$name] Fetching updates"
  if ! run_git -C "$abs_path" fetch "$remote" --prune; then
    echo "==> [$name] Fetch failed; continuing with the remaining projects" >&2
    return 1
  fi

  if [[ "$update" != "true" ]]; then
    echo "==> [$name] Update disabled, fetched only"
    return 0
  fi

  if ! dirty="$(git -C "$abs_path" status --porcelain)"; then
    echo "==> [$name] Could not inspect the working tree" >&2
    return 1
  fi
  if [[ -n "$dirty" ]]; then
    echo "==> [$name] Working tree has local changes, skipping pull"
    return 0
  fi

  current_branch="$(git -C "$abs_path" symbolic-ref --quiet --short HEAD || true)"
  if [[ -z "$current_branch" ]]; then
    echo "==> [$name] Detached HEAD, skipping pull"
    return 0
  fi

  if [[ -n "$branch" && "$current_branch" != "$branch" ]]; then
    echo "==> [$name] On branch $current_branch but expected $branch, skipping pull"
    return 0
  fi

  if [[ -n "$branch" ]]; then
    echo "==> [$name] Fast-forwarding $current_branch from $remote/$branch"
    if ! run_git -C "$abs_path" pull --ff-only "$remote" "$branch"; then
      echo "==> [$name] Fast-forward failed; continuing with the remaining projects" >&2
      return 1
    fi
    return 0
  fi

  if git -C "$abs_path" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    echo "==> [$name] Fast-forwarding tracked branch"
    if ! run_git -C "$abs_path" pull --ff-only; then
      echo "==> [$name] Fast-forward failed; continuing with the remaining projects" >&2
      return 1
    fi
  else
    echo "==> [$name] No upstream configured, fetched only"
  fi
}

failures=0
while IFS= read -r project; do
  if ! sync_project "$project"; then
    failures=$((failures + 1))
  fi
done < <(printf '%s' "$projects_json" | jq -c '.[]')

if (( failures > 0 )); then
  echo "==> $failures project(s) could not be synchronized" >&2
  exit 1
fi
