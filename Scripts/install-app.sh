#!/bin/sh
set -eu

source_app=${1:-}
installed_app=${2:-/Applications/WKRMacOS.app}

if [ -z "$source_app" ] || [ ! -d "$source_app" ]; then
    printf 'Source app was not found: %s\n' "$source_app" >&2
    exit 2
fi

bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$source_app/Contents/Info.plist")
if [ "$bundle_id" != 'io.github.yuhkis.wkr-macos' ]; then
    printf 'Unexpected bundle identifier: %s\n' "$bundle_id" >&2
    exit 2
fi

codesign --verify --deep --strict --verbose=2 "$source_app"

if [ -d "$installed_app" ]; then
    backup_app="${installed_app}.backup-$(date '+%Y%m%d-%H%M%S')"
    mv "$installed_app" "$backup_app"
    printf 'Previous app moved to: %s\n' "$backup_app"
fi

/usr/bin/ditto "$source_app" "$installed_app"
codesign --verify --deep --strict --verbose=2 "$installed_app"
printf 'Installed app: %s\n' "$installed_app"
