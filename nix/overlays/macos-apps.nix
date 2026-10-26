_final: prev:

let
  upstreamZenmap = prev.zenmap;
in
{
  zenmap = prev.symlinkJoin {
    pname = "zenmap";
    version = upstreamZenmap.version;
    name = "zenmap-${upstreamZenmap.version}";
    paths = [ upstreamZenmap ];
    postBuild = ''
      app="$out/Applications/Zenmap.app"
      mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
      ln -s ${upstreamZenmap}/bin/zenmap "$app/Contents/MacOS/Zenmap"
      cp ${upstreamZenmap}/share/pixmaps/zenmap.png "$app/Contents/Resources/Zenmap.png"
      cat >"$app/Contents/Info.plist" <<'PLIST'
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>CFBundleDisplayName</key>
        <string>Zenmap</string>
        <key>CFBundleExecutable</key>
        <string>Zenmap</string>
        <key>CFBundleIdentifier</key>
        <string>org.insecure.Zenmap</string>
        <key>CFBundleIconFile</key>
        <string>Zenmap.png</string>
        <key>CFBundleName</key>
        <string>Zenmap</string>
        <key>CFBundlePackageType</key>
        <string>APPL</string>
        <key>CFBundleShortVersionString</key>
        <string>${upstreamZenmap.version}</string>
        <key>CFBundleVersion</key>
        <string>${upstreamZenmap.version}</string>
        <key>NSHighResolutionCapable</key>
        <true/>
      </dict>
      </plist>
      PLIST
    '';
    meta = upstreamZenmap.meta;
  };
}
