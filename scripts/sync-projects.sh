#!/usr/bin/env bash
set -euo pipefail

projects_json=""
flake_dir=""
hostname=""
home_dir="${HOME:-}"

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

if [[ "$(printf '%s' "$projects_json" | jq 'length')" -eq 0 ]]; then
  echo "==> No projects configured"
  exit 0
fi

resolve_path() {
  local raw_path="$1"

  if [[ "$raw_path" == "~/"* ]]; then
    printf '%s/%s\n' "$home_dir" "${raw_path#\~/}"
  elif [[ "$raw_path" == /* ]]; then
    printf '%s\n' "$raw_path"
  else
    printf '%s/%s\n' "$home_dir" "$raw_path"
  fi
}

sync_project() {
  local project_json="$1"
  local name url path branch remote clone update abs_path parent_dir dirty current_branch

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
      git clone --branch "$branch" "$url" "$abs_path"
    else
      git clone "$url" "$abs_path"
    fi
    return 0
  fi

  if [[ ! -d "$abs_path/.git" ]]; then
    echo "==> [$name] $abs_path exists but is not a git repository, skipping"
    return 0
  fi

  echo "==> [$name] Fetching updates"
  git -C "$abs_path" fetch "$remote" --prune

  if [[ "$update" != "true" ]]; then
    echo "==> [$name] Update disabled, fetched only"
    return 0
  fi

  dirty="$(git -C "$abs_path" status --porcelain)"
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
    git -C "$abs_path" pull --ff-only "$remote" "$branch"
    return 0
  fi

  if git -C "$abs_path" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    echo "==> [$name] Fast-forwarding tracked branch"
    git -C "$abs_path" pull --ff-only
  else
    echo "==> [$name] No upstream configured, fetched only"
  fi
}

while IFS= read -r project; do
  sync_project "$project"
done < <(printf '%s' "$projects_json" | jq -c '.[]')
