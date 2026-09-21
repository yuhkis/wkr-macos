#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
configuration=${CONFIGURATION:-release}
flavor=${WKR_BUILD_FLAVOR:-v2}
case "$flavor" in
    v1) app_name=WKRV1; product=WKRMacOS; info=Info-v1.plist ;;
    v2) app_name=WKRPublic; product=WKRMacOS; info=Info.plist ;;
    practice) app_name=WakaraPractice; product=WKRPractice; info=Info-practice.plist ;;
    *) printf 'Unsupported build flavor\n' >&2; exit 1 ;;
esac
export WKR_BUILD_FLAVOR="$flavor"
scratch="$project_dir/.build/$flavor"
app_dir="$project_dir/build/$app_name.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"

cd "$project_dir"
# Remove the developer's local path from compiler-generated file/debug names.
swift build --scratch-path "$scratch" -c "$configuration" --product "$product" -debug-info-format none \
    -Xswiftc -debug-prefix-map -Xswiftc "$project_dir=." \
    -Xswiftc -file-prefix-map -Xswiftc "$project_dir=."
bin_dir=$(swift build --scratch-path "$scratch" -c "$configuration" --show-bin-path)

if [ -d "$app_dir" ]; then
    rm -rf "$app_dir"
fi
mkdir -p "$macos_dir"
cp "$project_dir/Resources/$info" "$contents_dir/Info.plist"
cp "$bin_dir/$product" "$macos_dir/$app_name"
chmod 755 "$macos_dir/$app_name"
if [ "$configuration" = release ]; then
    /usr/bin/strip -S "$macos_dir/$app_name"
fi
mkdir -p "$contents_dir/Resources"
if [ "$flavor" != v1 ]; then
    cp -R "$project_dir/Resources/Practice" "$contents_dir/Resources/Practice"
fi
if [ "$flavor" = v2 ] || [ "$flavor" = practice ]; then
    cp -R "$project_dir/Resources/Layout" "$contents_dir/Resources/Layout"
    cp "$project_dir/Resources/upstream-manifest.json" "$contents_dir/Resources/"
fi
cp "$project_dir/LICENSE" "$contents_dir/Resources/LICENSE"

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
    codesign --force --deep --sign - "$app_dir"
fi

codesign --verify --deep --strict --verbose=2 "$app_dir"
printf 'Built app: %s\n' "$app_dir"
