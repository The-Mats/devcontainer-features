#!/bin/bash
set -e
source dev-container-features-test-lib

# Feature options are readable only by install.sh, so the opt-out has to survive
# the trip to postCreate as a staged file. bootstrap.sh's own behaviour under
# RECONCILE_MCP=false is asserted in test.sh.
check "bootstrap.env staged" test -f /usr/local/share/claude-feature/bootstrap.env
check "reconcile turned off" bash -c \
    "grep -q '^RECONCILE_MCP=false$' /usr/local/share/claude-feature/bootstrap.env"

reportResults
