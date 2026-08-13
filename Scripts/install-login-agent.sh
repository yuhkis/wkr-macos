#!/bin/sh
set -eu

label=io.github.yuhkis.wkr-macos.login
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
source_plist="$project_dir/Resources/$label.plist"
target_dir="$HOME/Library/LaunchAgents"
target_plist="$target_dir/$label.plist"
domain="gui/$(id -u)"

test -x /Applications/WKRMacOS.app/Contents/MacOS/WKRMacOS || {
    printf 'Installed app was not found at /Applications/WKRMacOS.app.\n' >&2
    exit 2
}

plutil -lint "$source_plist"
mkdir -p "$target_dir"
launchctl bootout "$domain/$label" 2>/dev/null || true
install -m 0644 "$source_plist" "$target_plist"
launchctl bootstrap "$domain" "$target_plist"
launchctl enable "$domain/$label"
launchctl kickstart -k "$domain/$label"
launchctl print "$domain/$label" >/dev/null
printf 'Installed and started login agent: %s\n' "$target_plist"
