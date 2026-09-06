#!/bin/bash
set -e
source dev-container-features-test-lib

# Unconditional installs — the VS Code settings shipped by this feature depend
# on both, so a failure here means those settings point at nothing.
check "ripgrep on PATH at the hardcoded settings path" test -x /usr/bin/rg
check "ripgrep runs" bash -c "rg --version | grep -q ripgrep"
check "zsh installed for the terminal profile" bash -c "command -v zsh"

# `nvtop` is the default value of `packages`, which installs best-effort, so its
# absence is reported rather than failed — some base images do not carry it.
if command -v nvtop > /dev/null 2>&1; then
    echo "note: nvtop present"
else
    echo "note: nvtop absent on this base image (expected on some; installs best-effort)"
fi

reportResults
