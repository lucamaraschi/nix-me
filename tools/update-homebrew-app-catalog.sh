#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="$PROJECT_DIR/packages/app-state/catalog/homebrew-top-200-apps.json"
MARKDOWN_OUTPUT="$PROJECT_DIR/packages/app-state/catalog/homebrew-top-200-apps.md"
OVERRIDES="$PROJECT_DIR/packages/app-state/catalog/homebrew-behavior-overrides.json"
CHECK=false

if [[ "${1:-}" == "--check" ]]; then
    CHECK=true
elif [[ -n "${1:-}" ]]; then
    echo "usage: $0 [--check]" >&2
    exit 2
fi

for command in curl jq; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "error: $command is required" >&2
        exit 4
    }
done

CATALOG_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nix-me-cask-catalog.XXXXXX")"
trap 'find "$CATALOG_TMP_DIR" -depth -delete' EXIT
ANALYTICS="$CATALOG_TMP_DIR/analytics.json"
CASKS="$CATALOG_TMP_DIR/casks.json"
CANDIDATE="$CATALOG_TMP_DIR/catalog.json"
MARKDOWN_CANDIDATE="$CATALOG_TMP_DIR/catalog.md"

curl -fsSL https://formulae.brew.sh/api/analytics/cask-install/365d.json -o "$ANALYTICS"
curl -fsSL https://formulae.brew.sh/api/cask.json -o "$CASKS"

jq -n \
  --slurpfile analytics "$ANALYTICS" \
  --slurpfile casks "$CASKS" \
  --slurpfile overrides "$OVERRIDES" '
  def artifact_kinds($meta):
    [($meta.artifacts // [])[] | keys[]] | unique;
  def artifact_strings($meta):
    [($meta.artifacts // [])[] | .. | strings] | unique;
  def preference_paths($meta):
    [artifact_strings($meta)[] | select(test("^~/Library/Preferences/.+\\.plist"))];
  def config_paths($meta):
    [artifact_strings($meta)[] |
      select(test("(^~/\\.)|(^~/Library/Application Support/)") and
             (test("/Caches/|/HTTPStorages/|Saved Application State|sharedfilelist") | not))];
  def inferred_mechanism($prefs; $configs):
    if ($prefs | length) > 0 and ($configs | length) > 0 then "hybrid"
    elif ($prefs | length) > 0 then "defaults_dominant"
    elif ($configs | length) > 0 then "file_driven"
    else "cloud_or_opaque"
    end;
  def numeric_count: tostring | gsub(","; "") | tonumber;

  ($casks[0] | INDEX(.token)) as $by_token |
  ($overrides[0]) as $override_map |
  ([
    $analytics[0].items[] as $item |
    $by_token[$item.cask] as $meta |
    select($meta != null and any(($meta.artifacts // [])[]; has("app"))) |
    (preference_paths($meta)) as $prefs |
    (config_paths($meta)) as $configs |
    ($override_map[$item.cask] // {}) as $override |
    {
      analytics_rank: $item.number,
      cask: $item.cask,
      name: ($meta.name[0] // $item.cask),
      description: ($meta.desc // ""),
      homepage: ($meta.homepage // ""),
      installs: ($item.count | numeric_count),
      percent: ($item.percent | tonumber),
      artifact_kinds: artifact_kinds($meta),
      signals: {
        preference_paths: $prefs,
        config_paths: $configs
      },
      behavior: {
        mechanism: ($override.mechanism // inferred_mechanism($prefs; $configs)),
        confidence: ($override.confidence // (if (($prefs + $configs) | length) > 0 then "medium" else "low" end)),
        evidence: (if $override.note then "curated" elif (($prefs + $configs) | length) > 0 then "homebrew_zap_paths" else "homebrew_app_artifact" end),
        note: ($override.note // (if (($prefs + $configs) | length) > 0 then "Candidate mechanism inferred from paths in the current Homebrew cask zap stanza; capture must confirm which state is user-owned." else "No configuration path is exposed by the cask metadata; inspect with capture and export sniffing." end))
      },
      local_recipe: ($override.local_recipe // null)
    }
  ][:200] | to_entries | map(.value + {rank: (.key + 1)})) as $applications |
  {
    version: 1,
    source: {
      provider: "Homebrew Formulae Analytics",
      analytics_endpoint: "https://formulae.brew.sh/api/analytics/cask-install/365d.json",
      metadata_endpoint: "https://formulae.brew.sh/api/cask.json",
      window_days: 365,
      start_date: $analytics[0].start_date,
      end_date: $analytics[0].end_date,
      total_cask_events: ($analytics[0].total_count | numeric_count)
    },
    selection: {
      denominator: 200,
      rule: "First 200 analytics-ranked Homebrew/homebrew-cask entries whose current metadata contains an app artifact",
      excludes: "CLI-only tools, fonts, runtimes, drivers, and third-party tap entries without official Formulae metadata"
    },
    mechanisms: {
      defaults_dominant: "CFPreferences is the leading recipe candidate",
      file_driven: "User-owned structured or text files are the leading candidate",
      hybrid: "More than one mechanism is expected",
      cloud_or_opaque: "Cask metadata exposes no stable local configuration surface"
    },
    applications: $applications
  }
' > "$CANDIDATE"

if [[ "$(jq '.applications | length' "$CANDIDATE")" != "200" ]]; then
    echo "error: Homebrew data did not yield 200 application casks" >&2
    exit 5
fi

jq -r '
  ([.applications[].behavior.mechanism] | group_by(.) | map({key: .[0], value: length}) | from_entries) as $mechanisms |
  ([.applications[].behavior.confidence] | group_by(.) | map({key: .[0], value: length}) | from_entries) as $confidence |
  [
    "# Homebrew top-200 application configuration map",
    "",
    "Snapshot: **\(.source.start_date) through \(.source.end_date)** (365-day install window).",
    "",
    "This is the first 200 analytics-ranked official casks that install an `.app`; original Homebrew analytics rank is retained. Mechanisms: \($mechanisms | to_entries | map("\(.key)=\(.value)") | join(", ")); confidence: \($confidence | to_entries | map("\(.key)=\(.value)") | join(", ")).",
    "",
    "| App rank | Analytics rank | Cask | Installs | Mechanism | Confidence | Local recipe |",
    "|---:|---:|---|---:|---|---|---|"
  ] +
  [.applications[] |
    "| \(.rank) | \(.analytics_rank) | `\(.cask)` | \(.installs) | \(.behavior.mechanism) | \(.behavior.confidence) | \(.local_recipe // "—") |"
  ] | .[]
' "$CANDIDATE" > "$MARKDOWN_CANDIDATE"

if $CHECK; then
    if ! cmp -s "$CANDIDATE" "$OUTPUT" || ! cmp -s "$MARKDOWN_CANDIDATE" "$MARKDOWN_OUTPUT"; then
        echo "error: generated Homebrew catalog files are stale; run tools/update-homebrew-app-catalog.sh" >&2
        exit 3
    fi
    echo "Homebrew top-200 application catalog is current"
else
    mkdir -p "$(dirname "$OUTPUT")"
    mv "$CANDIDATE" "$OUTPUT"
    mv "$MARKDOWN_CANDIDATE" "$MARKDOWN_OUTPUT"
    echo "Updated $OUTPUT and $MARKDOWN_OUTPUT"
fi
