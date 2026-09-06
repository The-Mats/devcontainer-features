#!/bin/bash
set -e
source dev-container-features-test-lib

# shellVars widened to two names. Everything else in the file must still stay out
# of the shell. Asserted by set/unset — a test must never print a secret's value.
printf 'WANDB_API_KEY=fixture-wandb\nEXTRA_TOKEN=fixture-extra\nZOTERO_API_KEY=fixture-zotero\n' \
    > /home/vscode/.claude/secrets.env
chmod 600 /home/vscode/.claude/secrets.env

SNIP=/etc/profile.d/10-claude-secrets.sh

check "first allowlisted var exported" bash -c \
    'v=$(env -i PATH=$PATH sh -c ". '"$SNIP"'; echo \${WANDB_API_KEY-unset}"); [ "$v" = fixture-wandb ]'
check "second allowlisted var exported" bash -c \
    'v=$(env -i PATH=$PATH sh -c ". '"$SNIP"'; echo \${EXTRA_TOKEN-unset}"); [ "$v" = fixture-extra ]'
check "unlisted var still not exported" bash -c \
    'v=$(env -i PATH=$PATH sh -c ". '"$SNIP"'; echo \${ZOTERO_API_KEY-unset}"); [ "$v" = unset ]'

rm -f /home/vscode/.claude/secrets.env
reportResults
