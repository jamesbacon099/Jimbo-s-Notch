#!/bin/bash
set -euo pipefail
project="$(cd "$(dirname "$0")" && pwd)"
notch="${JIMBO_NOTCH_SOURCE:-$project/..}"
music="${JIMBO_MUSIC_SOURCE:-$project/../Jimbo Music}"
destination="${1:-$project/.build}"
mkdir -p "$destination" "$project/.build/module-cache"
staging="$(mktemp -d "$destination/.studio-build.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
bundle="$staging/Jimbo's Notch Buddy.app"
app="$destination/Jimbo's Notch Buddy.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$project/Info.plist" "$bundle/Contents/Info.plist"
cp "$notch/Resources/AppIcon.icns" "$bundle/Contents/Resources/AppIcon.icns"
preferences="${JIMBO_BUNDLED_PREFERENCES:-$project/BundledPreferences.plist}"
plutil -lint "$preferences"
cp "$preferences" "$bundle/Contents/Resources/BundledPreferences.plist"
sources=()
for source in "$notch"/Sources/NotchBeat/*.swift; do
    [[ "$(basename "$source")" == NotchBeatApp.swift ]] || sources+=("$source")
done
xcrun swiftc -swift-version 5 -O -parse-as-library -D JIMBO_STUDIO \
    -target "$(uname -m)-apple-macosx14.2" \
    -module-cache-path "$project/.build/module-cache" \
    "${sources[@]}" "$music"/Sources/*.swift "$project"/Sources/*.swift -o "$bundle/Contents/MacOS/JimboStudio"
codesign --force --sign - "$bundle"
codesign --verify --strict "$bundle"
if [[ -e "$app" ]]; then mv "$app" "$staging/Previous.app"; fi
if ! mv "$bundle" "$app"; then
    if [[ -e "$staging/Previous.app" ]]; then mv "$staging/Previous.app" "$app"; fi
    exit 1
fi
printf '%s\n' "$app"
