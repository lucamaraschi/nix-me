{ lib
, swiftPackages
, swift
, swiftpm
, nixMeApps
}:

swiftPackages.stdenv.mkDerivation {
  pname = "nix-me-macos";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.unions [
      (lib.fileset.difference
        ../../apps/macos/NixMeApp
        (lib.fileset.maybeMissing ../../apps/macos/NixMeApp/.build))
      ../../packages/management-api/bin
    ];
  };

  nativeBuildInputs = [
    swift
    swiftpm
  ];

  env.MACOSX_DEPLOYMENT_TARGET = "14.0";

  dontConfigure = true;
  dontStrip = true;

  buildPhase = ''
    runHook preBuild

    export HOME="$TMPDIR/home"
    export NIX_ME_DISABLE_SPARKLE=1
    mkdir -p "$HOME" "$TMPDIR/swift-cache" "$TMPDIR/swift-config" "$TMPDIR/swift-security"

    swift build \
      --package-path apps/macos/NixMeApp \
      --configuration release \
      --disable-sandbox \
      --cache-path "$TMPDIR/swift-cache" \
      --config-path "$TMPDIR/swift-config" \
      --security-path "$TMPDIR/swift-security" \
      --scratch-path "$TMPDIR/swift-build" \
      --product NixMeApp

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    app="$out/Applications/Nix Me.app"
    contents="$app/Contents"
    package="apps/macos/NixMeApp"
    binary="$(swift build \
      --package-path "$package" \
      --configuration release \
      --disable-sandbox \
      --cache-path "$TMPDIR/swift-cache" \
      --config-path "$TMPDIR/swift-config" \
      --security-path "$TMPDIR/swift-security" \
      --scratch-path "$TMPDIR/swift-build" \
      --show-bin-path)/NixMeApp"

    mkdir -p "$contents/MacOS" "$contents/Resources/management-api"
    install -m 0755 "$binary" "$contents/MacOS/NixMeApp"
    install -m 0644 "$package/App/Info.plist" "$contents/Info.plist"

    iconset="$TMPDIR/NixMe.iconset"
    mkdir -p "$iconset"
    while read -r filename size; do
      /usr/bin/sips -z "$size" "$size" "$package/App/AppIcon.png" \
        --out "$iconset/$filename" >/dev/null
    done <<'EOF'
    icon_16x16.png 16
    icon_16x16@2x.png 32
    icon_32x32.png 32
    icon_32x32@2x.png 64
    icon_128x128.png 128
    icon_128x128@2x.png 256
    icon_256x256.png 256
    icon_256x256@2x.png 512
    icon_512x512.png 512
    icon_512x512@2x.png 1024
    EOF
    /usr/bin/iconutil -c icns "$iconset" -o "$contents/Resources/NixMe.icns"

    install -m 0755 \
      packages/management-api/bin/nix-me-api \
      packages/management-api/bin/nix-me-action \
      packages/management-api/bin/nix-me-details \
      "$contents/Resources/management-api/"
    install -m 0755 \
      ${nixMeApps}/bin/nix-me-apps \
      "$contents/Resources/management-api/nix-me-apps"

    /usr/libexec/PlistBuddy -c "Delete :SUEnableAutomaticChecks" "$contents/Info.plist" || true
    /usr/libexec/PlistBuddy -c "Delete :SUFeedURL" "$contents/Info.plist" || true
    /usr/libexec/PlistBuddy -c "Delete :SUPublicEDKey" "$contents/Info.plist" || true
    /usr/bin/plutil -lint "$contents/Info.plist" >/dev/null

    runHook postInstall
  '';

  postFixup = ''
    app="$out/Applications/Nix Me.app"
    /usr/bin/codesign --force --sign - --timestamp=none "$app"
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
  '';

  meta = {
    description = "Native Nix Me macOS system manager";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
  };
}
