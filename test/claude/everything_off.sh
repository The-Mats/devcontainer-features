#!/bin/bash
set -e
source dev-container-features-test-lib

# Both options off. The mount point, CLAUDE_CONFIG_DIR and the shell snippet are
# not optional — they are what makes the volume useful at all — so they survive.
check "config dir still created" test -d /home/vscode/.claude
check "CLAUDE_CONFIG_DIR still set" bash -c '[ "$CLAUDE_CONFIG_DIR" = "/home/vscode/.claude" ]'
check "profile snippet still installed" test -f /etc/profile.d/10-claude-secrets.sh

check "no managed settings written" bash -c "! test -f /etc/claude-code/managed-settings.json"
check "no definitions staged" bash -c "! test -f /usr/local/share/claude-feature/mcp-servers.json"

# postCreateCommand names bootstrap.sh unconditionally, so it must exist and exit
# cleanly with nothing staged, or every container create reports a failure.
check "bootstrap still installed" test -x /usr/local/share/claude-feature/bootstrap.sh
check "bootstrap exits cleanly with nothing staged" /usr/local/share/claude-feature/bootstrap.sh

# jq is pulled in only to drive the MCP bootstrap, so it should not be here.
check "jq not installed when unused" bash -c "! command -v jq"

reportResults
