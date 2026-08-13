#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
configuration=${CONFIGURATION:-release}
app_dir="$project_dir/build/WKRMacOS.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"

cd "$project_dir"
swift build -c "$configuration" --product WKRMacOS
bin_dir=$(swift build -c "$configuration" --show-bin-path)

if [ -d "$app_dir" ]; then
    rm -rf "$app_dir"
fi
mkdir -p "$macos_dir"
cp "$project_dir/Resources/Info.plist" "$contents_dir/Info.plist"
cp "$bin_dir/WKRMacOS" "$macos_dir/WKRMacOS"
chmod 755 "$macos_dir/WKRMacOS"

# Signing is opt-in. The keychain may hold certificates that belong to another
# person or business, and silently picking one would publish this app under
# their identity. Set CODESIGN_IDENTITY to sign with a specific certificate you
# own; leave it unset for ad-hoc signing.
identity=${CODESIGN_IDENTITY:-}

if [ -n "$identity" ] && [ "$identity" != '-' ]; then
    printf 'Signing with requested identity: %s\n' "$identity"
    codesign --force --deep --options runtime --timestamp --sign "$identity" "$app_dir"
else
    printf 'Using ad-hoc signing (set CODESIGN_IDENTITY to sign with your own certificate).\n'
    printf 'A rebuild may require Input Monitoring/Accessibility permission to be granted again.\n'
    available=$(security find-identity -v -p codesigning 2>/dev/null |
        awk -F\" '/"(Apple Development|Developer ID Application):/{print "  " $2}')
    if [ -n "$available" ]; then
        printf 'Certificates available in this keychain:\n%s\n' "$available"
        printf 'Only use one that is issued to you.\n'
    fi
    codesign --force --deep --sign - "$app_dir"
fi

codesign --verify --deep --strict --verbose=2 "$app_dir"
printf 'Built app: %s\n' "$app_dir"
