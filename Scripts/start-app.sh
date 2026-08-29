#!/bin/sh
# Launch the app, retrying until it stays running.
#
# The app is deliberately fail closed: when Input Monitoring or Accessibility is
# missing it asks for them and terminates, because `CGRequestListenEventAccess`
# returns before the user has answered. A newly built bundle has a new ad-hoc
# signature and therefore no permissions, so the first launch after every
# rebuild always ends that way and the app has to be started again by hand.
#
# Retrying here keeps that safety rule inside the app while removing the manual
# step: each attempt is a fresh process, so the permission is picked up as soon
# as it is granted, whether or not a running process would have seen it.
set -eu

app=${1:-}
shift || true

if [ -z "$app" ] || [ ! -d "$app" ]; then
    printf 'App was not found: %s\n' "$app" >&2
    exit 2
fi

attempt_interval=${WKR_START_RETRY_INTERVAL:-5}
timeout=${WKR_START_TIMEOUT:-300}
settle=2
confirm=2

elapsed=0
announced=0
first=1

while :; do
    # `open` itself can fail transiently with -600 (procNotFound) right after
    # install-app.sh replaces the bundle: Launch Services still points at the
    # moved copy for a moment. Under `set -e` that single failure used to kill
    # the script before the retry loop — the loop that exists precisely for
    # flaky startups — ever ran once. Treat it like any other failed attempt.
    if ! open "$app" --args "$@"; then
        printf 'open failed (Launch Services may still be settling after the bundle was replaced); retrying.\n' >&2
        elapsed=$((elapsed + attempt_interval))
        if [ "$elapsed" -ge "$timeout" ]; then
            printf 'Gave up after %s seconds: open kept failing.\n' "$timeout" >&2
            exit 1
        fi
        sleep "$attempt_interval"
        continue
    fi

    if [ "$first" -eq 1 ]; then
        first=0
        # Ask for the permissions once, on the first attempt only. Requesting
        # again every few seconds buries System Settings under a fresh prompt
        # and makes the switch the user is reaching for impossible to click.
        # Later attempts only need the permission to already be there.
        count=$#
        while [ "$count" -gt 0 ]; do
            argument=$1
            shift
            if [ "$argument" != "--request-permissions" ]; then
                set -- "$@" "$argument"
            fi
            count=$((count - 1))
        done
    fi

    sleep "$settle"

    if pgrep -x WKRMacOS >/dev/null 2>&1; then
        # A missing permission makes the app exit on its own, and the process
        # is still listed while it does. Look again before believing it.
        sleep "$confirm"
        if pgrep -x WKRMacOS >/dev/null 2>&1; then
            printf 'Started: %s\n' "$app"
            exit 0
        fi
    fi

    if [ "$announced" -eq 0 ]; then
        announced=1
        cat >&2 <<'MESSAGE'
The app asked for permission and exited, which is its normal fail-closed path.

Grant both of these in System Settings > Privacy & Security, then leave this
running; it retries on its own and stops as soon as the app stays up. The
permission request is only made on the first attempt, so the panel stays
usable while you work through it.

  - Input Monitoring
  - Accessibility

A rebuilt bundle has a new signature, so an existing entry can look enabled
while being stale. Remove it with the minus button and add it again.
MESSAGE
    fi

    elapsed=$((elapsed + settle + attempt_interval))
    if [ "$elapsed" -ge "$timeout" ]; then
        printf 'Gave up after %s seconds. Check: /usr/bin/log show --predicate '"'"'subsystem == "io.github.yuhkis.wkr-macos"'"'"' --last 5m --style compact\n' "$timeout" >&2
        exit 1
    fi
    sleep "$attempt_interval"
done
