#!/bin/bash

set -euo pipefail

VERSION="${1:-}"
DMG_PATH="${2:-}"
OUTPUT_PATH="${3:-nix-me.rb}"

if [[ -z "$VERSION" || ! -f "$DMG_PATH" ]]; then
  echo "Usage: $0 VERSION /path/to/Nix-Me-VERSION.dmg [output.rb]" >&2
  exit 64
fi

SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"

mkdir -p "$(dirname "$OUTPUT_PATH")"
cat >"$OUTPUT_PATH" <<EOF
cask "nix-me" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/lucamaraschi/nix-me/releases/download/v#{version}/Nix-Me-#{version}.dmg"
  name "Nix Me"
  desc "Manage a declarative macOS configuration"
  homepage "https://github.com/lucamaraschi/nix-me"

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Nix Me.app"

  zap trash: [
    "~/Library/Caches/com.nix-me.manager",
    "~/Library/Preferences/com.nix-me.manager.plist",
  ]
end
EOF

echo "Generated $OUTPUT_PATH"
