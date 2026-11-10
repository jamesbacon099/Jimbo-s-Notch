#!/bin/bash
set -euo pipefail

project="$(cd "$(dirname "$0")" && pwd)"
destination="${1:-$project/.build}"
mkdir -p "$destination" "$project/.build/module-cache"
destination="$(cd "$destination" && pwd)"
app="$destination/NotchBeat.app"
staging="$(mktemp -d "$destination/.notchbeat-build.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
bundle="$staging/NotchBeat.app"

mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$project/Info.plist" "$bundle/Contents/Info.plist"
cp "$project/Resources/AppIcon.icns" "$bundle/Contents/Resources/AppIcon.icns"
xcrun swiftc -swift-version 5 -O -parse-as-library \
    -target "$(uname -m)-apple-macosx14.2" \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -module-cache-path "$project/.build/module-cache" \
    -module-name NotchBeat \
    "$project"/Sources/NotchBeat/*.swift -o "$bundle/Contents/MacOS/NotchBeat"
codesign --force --sign "${NOTCHBEAT_SIGN_IDENTITY:--}" "$bundle"
codesign --verify --strict "$bundle"

# Keep an existing app intact if compilation or signing fails.
if [[ -e "$app" ]]; then
    mv "$app" "$staging/previous.app"
    if ! mv "$bundle" "$app"; then
        mv "$staging/previous.app" "$app"
        exit 1
    fi
else
    mv "$bundle" "$app"
fi
printf '%s\n' "$app"
