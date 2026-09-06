#!/usr/bin/env bash
#
# Runs as root during image build. See
# https://containers.dev/implementors/features/#invoking-installsh
set -euo pipefail

echo "Activating feature 'workbench'"

# ripgrep and zsh are not optional: the feature's `customizations.vscode.settings`
# hardcode /usr/bin/rg and a zsh terminal profile, and feature metadata takes no
# option substitution — there is no way to make those settings conditional on an
# option, so the packages they depend on are always installed.
REQUIRED="ripgrep zsh"
EXTRA="$(echo "${PACKAGES:-}" | tr ',' ' ')"

if ! command -v apt-get > /dev/null 2>&1; then
    echo "ERROR: 'workbench' supports Debian-family images only (apt-get not found)." >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -y

# One package at a time, so a name missing from this base image's repositories
# (nvtop lives in Ubuntu's universe component, which not every image enables)
# is skipped with a warning instead of failing the whole container build.
skipped=""
for pkg in $REQUIRED $EXTRA; do
    [ -n "$pkg" ] || continue
    if apt-get install -y --no-install-recommends "$pkg"; then
        echo "  installed: $pkg"
    else
        echo "  WARNING: could not install '$pkg' — skipping" >&2
        skipped="$skipped $pkg"
    fi
done

rm -rf /var/lib/apt/lists/*

if [ -n "$skipped" ]; then
    echo "Finished with skipped packages:$skipped"
else
    echo "Finished; all packages installed."
fi
