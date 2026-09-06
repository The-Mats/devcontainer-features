#!/bin/bash
set -e
source dev-container-features-test-lib

# The two features are meant to be installed together; this checks neither
# clobbers the other's files or packages.

# claude
check "config dir" test -d /home/vscode/.claude
check "managed settings" test -f /etc/claude-code/managed-settings.json
check "definitions staged" test -f /usr/local/share/claude-feature/mcp-servers.json

# workbench
check "ripgrep at the path its settings hardcode" test -x /usr/bin/rg
check "zsh for the terminal profile" bash -c "command -v zsh"
check "jq from workbench packages" bash -c "jq --version"

reportResults
