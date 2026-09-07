#!/bin/bash
set -e
source dev-container-features-test-lib

# --- volume mount point -------------------------------------------------------
# Created by install.sh before the volume attaches, so a fresh volume inherits
# this ownership instead of coming up root-owned.
check "config dir exists" test -d /home/vscode/.claude
check "CLAUDE_CONFIG_DIR points at it" bash -c '[ "$CLAUDE_CONFIG_DIR" = "/home/vscode/.claude" ]'

# --- managed deny rules (default: on) ----------------------------------------
check "managed settings installed" test -f /etc/claude-code/managed-settings.json
check "managed settings are valid JSON" bash -c "jq -e . /etc/claude-code/managed-settings.json > /dev/null"
# Only the Read rules are paths; a relative one in a non-project settings file
# resolves against that file's directory and would match nothing.
check "every Read deny path is absolute" bash -c \
    "jq -e '.permissions.deny | map(select(startswith(\"Read(\"))) | all(startswith(\"Read(//\"))' /etc/claude-code/managed-settings.json > /dev/null"
check "printenv denied" bash -c \
    "jq -e '.permissions.deny | any(startswith(\"Bash(printenv\"))' /etc/claude-code/managed-settings.json > /dev/null"
# env* would also match envsubst and envdir, so it is deliberately not here.
check "env not blanket-denied" bash -c \
    "jq -e '.permissions.deny | any(. == \"Bash(env*)\") | not' /etc/claude-code/managed-settings.json > /dev/null"
# Neither of these matches *secret*, and both hold credentials, so they must be
# denied by name or they are not covered at all.
check "settings.json denied by name" bash -c \
    "jq -e '.permissions.deny | any(contains(\"settings.json\"))' /etc/claude-code/managed-settings.json > /dev/null"
check "credentials denied by name" bash -c \
    "jq -e '.permissions.deny | any(contains(\".credentials.json\"))' /etc/claude-code/managed-settings.json > /dev/null"

# --- secrets on the shell PATH -----------------------------------------------
check "profile snippet installed" test -f /etc/profile.d/10-claude-secrets.sh
check "profile snippet is valid shell" bash -n /etc/profile.d/10-claude-secrets.sh
check "profile snippet tolerates a missing secrets file" bash -c \
    ". /etc/profile.d/10-claude-secrets.sh"
check "interactive non-login shells hooked" bash -c \
    "grep -q 10-claude-secrets /etc/bash.bashrc"
# zsh may be installed later — by the workbench feature ordered after this one,
# or by a dotfiles script at container create — so the hook must already be in
# place. For a zsh terminal this is the hook that works; profile.d is login-only.
check "zsh rc hooked even if zsh is not installed yet" bash -c \
    "grep -q 10-claude-secrets /etc/zsh/zshrc"

# The shell gets an allowlist, not the whole file: only what a typed command
# needs. Asserted by set/unset, never by printing a value.
printf 'WANDB_API_KEY=fixture-wandb\nZOTERO_API_KEY=fixture-zotero\n' \
    > /home/vscode/.claude/secrets.env
chmod 600 /home/vscode/.claude/secrets.env
check "allowlisted var is exported" bash -c \
    'v=$(env -i PATH=$PATH sh -c ". /etc/profile.d/10-claude-secrets.sh; echo \${WANDB_API_KEY-unset}"); [ "$v" = fixture-wandb ]'
check "non-allowlisted var is NOT exported" bash -c \
    'v=$(env -i PATH=$PATH sh -c ". /etc/profile.d/10-claude-secrets.sh; echo \${ZOTERO_API_KEY-unset}"); [ "$v" = unset ]'
# Any output here breaks powerlevel10k's instant prompt.
check "sourcing the snippet is silent" bash -c \
    '[ -z "$(env -i PATH=$PATH sh -c ". /etc/profile.d/10-claude-secrets.sh" 2>&1)" ]'
rm -f /home/vscode/.claude/secrets.env

# --- MCP definitions (default: on) -------------------------------------------
check "bootstrap is executable" test -x /usr/local/share/claude-feature/bootstrap.sh
check "definitions staged" test -f /usr/local/share/claude-feature/mcp-servers.json
check "definitions are valid JSON" bash -c "jq -e '.mcpServers' /usr/local/share/claude-feature/mcp-servers.json > /dev/null"
# github uses a PAT, not OAuth: api.githubcopilot.com/mcp/ has no dynamic client
# registration, which `claude mcp login` requires. Every server must therefore
# carry a ${VAR} reference and never a literal.
check "github credential is a \${VAR} reference" bash -c \
    "jq -e '.mcpServers.github.headers.Authorization == \"Bearer \${GITHUB_PERSONAL_ACCESS_TOKEN}\"' /usr/local/share/claude-feature/mcp-servers.json > /dev/null"
check "wandb credential is a \${VAR} reference" bash -c \
    "jq -e '.mcpServers.wandb.headers.Authorization == \"Bearer \${WANDB_API_KEY}\"' /usr/local/share/claude-feature/mcp-servers.json > /dev/null"
check "zotero credential is a \${VAR} reference" bash -c \
    "jq -e '.mcpServers.zotero.env.ZOTERO_API_KEY == \"\${ZOTERO_API_KEY}\"' /usr/local/share/claude-feature/mcp-servers.json > /dev/null"
check "no literal keys committed" bash -c \
    "! grep -qE '(sk-|ghp_|github_pat_|wandb_v1_)' /usr/local/share/claude-feature/mcp-servers.json"

# --- bootstrap behaviour ------------------------------------------------------
# No secrets.env and no claude CLI in the test image: it must still exit 0.
check "bootstrap exits cleanly with no secrets file" /usr/local/share/claude-feature/bootstrap.sh
# Not "settings.json must not exist": the claude CLI arrives via dependsOn and may
# write into the config dir itself. What matters is that bootstrap invented no env
# block when there was no secrets.env to build one from.
check "no env block without a secrets file" bash -c \
    "! test -f /home/vscode/.claude/settings.json || jq -e '(.env // {}) | length == 0' /home/vscode/.claude/settings.json > /dev/null"

# Now with a secrets file, the env block must be generated from it.
printf '# a comment\n\nWANDB_API_KEY=abc123\nZOTERO_LIBRARY_ID=42\n' > /home/vscode/.claude/secrets.env
chmod 600 /home/vscode/.claude/secrets.env
CLAUDE_CONFIG_DIR=/home/vscode/.claude /usr/local/share/claude-feature/bootstrap.sh
check "env block generated" bash -c \
    "jq -e '.env.WANDB_API_KEY == \"abc123\" and .env.ZOTERO_LIBRARY_ID == \"42\"' /home/vscode/.claude/settings.json > /dev/null"
check "comments and blank lines skipped" bash -c \
    "jq -e '.env | length == 2' /home/vscode/.claude/settings.json > /dev/null"
check "generated settings are mode 600" bash -c \
    "[ \"\$(stat -c '%a' /home/vscode/.claude/settings.json)\" = 600 ]"

# Re-running must merge, not clobber, whatever else lives in settings.json.
jq '. + {model: "opus"}' /home/vscode/.claude/settings.json > /tmp/s && mv /tmp/s /home/vscode/.claude/settings.json
CLAUDE_CONFIG_DIR=/home/vscode/.claude /usr/local/share/claude-feature/bootstrap.sh
check "existing settings keys preserved" bash -c \
    "jq -e '.model == \"opus\" and .env.WANDB_API_KEY == \"abc123\"' /home/vscode/.claude/settings.json > /dev/null"

# --- MCP reconcile ------------------------------------------------------------
# Options are only visible to install.sh, so bootstrap.sh reads them from here.
check "bootstrap.env staged" test -f /usr/local/share/claude-feature/bootstrap.env
check "reconcile defaults to on" bash -c \
    "grep -q '^RECONCILE_MCP=true$' /usr/local/share/claude-feature/bootstrap.env"

# A stand-in for `claude mcp`, writing the same file the real CLI writes. The real
# one only arrives via dependsOn, and these assertions are about bootstrap's own
# add/reconcile decisions, not about the CLI.
STUB=/tmp/mcpstub
mkdir -p "$STUB"
cat > "$STUB/claude" <<'STUBEOF'
#!/bin/bash
cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.claude.json"
[ -s "$cfg" ] || echo '{}' > "$cfg"
case "$2" in
    add-json) jq --arg n "$3" --argjson d "$4" '.mcpServers[$n] = $d' "$cfg" > "$cfg.t" && mv "$cfg.t" "$cfg" ;;
    remove)   jq --arg n "$3" 'del(.mcpServers[$n])' "$cfg" > "$cfg.t" && mv "$cfg.t" "$cfg" ;;
    get)      jq -e --arg n "$3" '.mcpServers[$n]' "$cfg" > /dev/null ;;
    *)        exit 0 ;;
esac
STUBEOF
chmod +x "$STUB/claude"

# An isolated config dir: these tests rewrite .claude.json, and the assertions
# above are about the real one.
T=/tmp/reconcile-home
rm -rf "$T"; mkdir -p "$T"
run_bootstrap() { PATH="$STUB:$PATH" CLAUDE_CONFIG_DIR="$T" \
    /usr/local/share/claude-feature/bootstrap.sh > /tmp/boot.log 2>&1; }

# First run on an empty volume: every staged server is added.
run_bootstrap
check "fresh run adds every staged server" bash -c \
    'a=$(jq -r ".mcpServers | keys | length" /tmp/reconcile-home/.claude.json); b=$(jq -r ".mcpServers | keys | length" /usr/local/share/claude-feature/mcp-servers.json); [ "$a" = "$b" ]'
check "fresh run reports an add" bash -c "grep -q \"'github' added\" /tmp/boot.log"

# Second run, nothing changed: no churn and no backups.
run_bootstrap
check "unchanged servers are left alone" bash -c \
    "grep -q \"'github' already up to date\" /tmp/boot.log"
check "no backup written when nothing drifted" bash -c \
    "! test -d /tmp/reconcile-home/mcp-backups"

# The regression this guards: the OAuth-era github entry, correct definition
# staged, name already present. Skipping on the name alone stranded it forever.
jq '.mcpServers.github = {"type":"http","url":"https://api.githubcopilot.com/mcp/"}' \
    "$T/.claude.json" > "$T/x" && mv "$T/x" "$T/.claude.json"
run_bootstrap
check "a drifted server is reconciled" bash -c \
    'jq -e ".mcpServers.github.headers.Authorization == \"Bearer \${GITHUB_PERSONAL_ACCESS_TOKEN}\"" /tmp/reconcile-home/.claude.json > /dev/null'
check "reconcile is reported" bash -c "grep -q \"'github' reconciled\" /tmp/boot.log"
# Drift may be a deliberate local edit, so the old entry is kept, not discarded.
check "previous entry backed up" bash -c \
    'ls /tmp/reconcile-home/mcp-backups/github.*.json > /dev/null 2>&1'
check "backup holds the entry that was replaced" bash -c \
    'jq -e "has(\"headers\") | not" $(ls /tmp/reconcile-home/mcp-backups/github.*.json | head -1) > /dev/null'
check "backup is mode 600" bash -c \
    '[ "$(stat -c %a $(ls /tmp/reconcile-home/mcp-backups/github.*.json | head -1))" = 600 ]'
# Servers the user added by hand are none of this Feature's business.
check "unstaged servers are untouched" bash -c \
    'jq --arg n mine ".mcpServers[\$n] = {\"command\":\"x\"}" /tmp/reconcile-home/.claude.json > /tmp/y && mv /tmp/y /tmp/reconcile-home/.claude.json; PATH=/tmp/mcpstub:$PATH CLAUDE_CONFIG_DIR=/tmp/reconcile-home /usr/local/share/claude-feature/bootstrap.sh > /dev/null 2>&1; jq -e ".mcpServers.mine.command == \"x\"" /tmp/reconcile-home/.claude.json > /dev/null'

# reconcileMcp=false: drift is reported and left in place. Asserted here by
# swapping the staged file; the mcp_reconcile_off scenario covers install.sh.
cp /usr/local/share/claude-feature/bootstrap.env /tmp/bootstrap.env.bak
echo 'RECONCILE_MCP=false' > /usr/local/share/claude-feature/bootstrap.env
jq '.mcpServers.github = {"type":"http","url":"https://api.githubcopilot.com/mcp/"}' \
    "$T/.claude.json" > "$T/x" && mv "$T/x" "$T/.claude.json"
run_bootstrap
check "reconcileMcp=false leaves drift in place" bash -c \
    'jq -e ".mcpServers.github | has(\"headers\") | not" /tmp/reconcile-home/.claude.json > /dev/null'
check "reconcileMcp=false says so" bash -c "grep -q 'reconcileMcp=false' /tmp/boot.log"
cp /tmp/bootstrap.env.bak /usr/local/share/claude-feature/bootstrap.env
rm -rf "$T" "$STUB" /tmp/boot.log /tmp/bootstrap.env.bak

# The CLI arrives via dependsOn; report rather than fail, so a registry hiccup
# fetching that feature does not read as a bug in this one.
if command -v claude > /dev/null 2>&1; then
    echo "note: claude CLI present"
else
    echo "note: claude CLI absent — dependsOn feature did not resolve"
fi

reportResults
