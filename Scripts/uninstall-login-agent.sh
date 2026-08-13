#!/bin/sh
set -eu

label=io.github.yuhkis.wkr-macos.login
target_plist="$HOME/Library/LaunchAgents/$label.plist"
domain="gui/$(id -u)"

launchctl bootout "$domain/$label" 2>/dev/null || true
if [ -e "$target_plist" ]; then
    rm "$target_plist"
fi
printf 'Removed login agent: %s\n' "$target_plist"
