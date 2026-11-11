#!/bin/bash
set -euo pipefail
project="$(cd "$(dirname "$0")" && pwd)"
destination="${1:-$project/.build}"
mkdir -p "$destination" "$project/.build/module-cache"
staging="$(mktemp -d "$destination/.jimbo-music.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
app="$staging/Jimbo Music.app"
mkdir -p "$app/Contents/MacOS"
cp "$project/Info.plist" "$app/Contents/Info.plist"
xcrun swiftc -swift-version 5 -O -parse-as-library \
    -target "$(uname -m)-apple-macosx14.2" \
    -module-cache-path "$project/.build/module-cache" \
    "$project"/Sources/*.swift -o "$app/Contents/MacOS/JimboMusic"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
ditto "$app" "$destination/Jimbo Music.app"
printf '%s\n' "$destination/Jimbo Music.app"
