#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
app_dir="$project_dir/build/WKRV1Archive.app"
if [ -e "$app_dir" ]; then
    printf 'Archive app output already exists; preserve it and use a fresh source directory.\n' >&2
    exit 2
fi
cd "$project_dir"
swift build -c release --product WKRMacOS -debug-info-format none \
    -Xswiftc -debug-prefix-map -Xswiftc "$project_dir=." \
    -Xswiftc -file-prefix-map -Xswiftc "$project_dir=."
bin_dir=$(swift build -c release --show-bin-path)
mkdir -p "$app_dir/Contents/MacOS"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
cp "$bin_dir/WKRMacOS" "$app_dir/Contents/MacOS/WKRV1Archive"
chmod 755 "$app_dir/Contents/MacOS/WKRV1Archive"
/usr/bin/strip -S "$app_dir/Contents/MacOS/WKRV1Archive"
codesign --force --deep --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
printf 'Built build/WKRV1Archive.app; not installed or launched.\n'
