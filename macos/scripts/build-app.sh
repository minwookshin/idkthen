#!/bin/bash
set -euo pipefail
idkthen_root="$(cd "$(dirname "$0")/.." && pwd)"
idkthen_output="${1:-$idkthen_root/../build/idkthen.app}"
idkthen_build="${2:-$idkthen_root/.build}"
swift build --package-path "$idkthen_root" --scratch-path "$idkthen_build" -c release
idkthen_bin="$(swift build --package-path "$idkthen_root" --scratch-path "$idkthen_build" -c release --show-bin-path)"
mkdir -p "$idkthen_output/Contents/MacOS" "$idkthen_output/Contents/Resources" "$idkthen_build/idkthen.iconset"
cp "$idkthen_bin/idkthen" "$idkthen_output/Contents/MacOS/idkthen"
swift "$idkthen_root/scripts/make-icon.swift" "$idkthen_build/idkthen.iconset"
iconutil -c icns "$idkthen_build/idkthen.iconset" -o "$idkthen_output/Contents/Resources/idkthen.icns"
cat > "$idkthen_output/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>idkthen</string>
<key>CFBundleDisplayName</key><string>idkthen</string>
<key>CFBundleExecutable</key><string>idkthen</string>
<key>CFBundleIdentifier</key><string>dev.pairtype.preview</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.18.0</string>
<key>CFBundleVersion</key><string>28</string>
<key>CFBundleIconFile</key><string>idkthen</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
# A consistent development identity avoids discarding Accessibility approval on
# each local update. Distribution signing remains the release script's job.
codesign --force --sign "${IDKTHEN_SIGN_IDENTITY:--}" "$idkthen_output"
codesign --verify --strict "$idkthen_output"
printf 'Built: %s\n' "$idkthen_output"
