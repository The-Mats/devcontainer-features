#!/bin/bash
set -e
source dev-container-features-test-lib

check "jq from packages" bash -c "jq --version"
check "tmux from packages" bash -c "tmux -V"
check "ripgrep still installed" test -x /usr/bin/rg
check "zsh still installed" bash -c "command -v zsh"

reportResults
