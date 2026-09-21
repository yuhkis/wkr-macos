#!/bin/sh
# Open the Public bundle once; its setup window handles permission retries.
set -eu
app=${1:-}
shift || true
if [ -z "$app" ] || [ ! -d "$app" ]; then
    printf 'App was not found: %s\n' "$app" >&2
    exit 2
fi
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")
if [ "$bundle_id" != 'io.github.yuhkis.wkr-macos.public' ]; then
    printf 'Expected a WKR macOS Public bundle.\n' >&2
    exit 2
fi
open "$app" --args "$@"
printf 'Opened Public. Confirm permissions and conversion status in its window/menu.\n'
