#!/bin/bash
set -e
source dev-container-features-test-lib

# An empty `packages` must still leave the two the VS Code settings depend on.
check "ripgrep installed with empty packages" test -x /usr/bin/rg
check "zsh installed with empty packages" bash -c "command -v zsh"

reportResults
