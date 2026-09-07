#!/usr/bin/env bash
#
# postCreateCommand for the 'claude' feature. Runs as the remote user, after the
# volume is mounted, so everything it reads and writes is persistent.
set -uo pipefail

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-/home/vscode/.claude}"
DEFS="/usr/local/share/claude-feature/mcp-servers.json"
SECRETS="$CONFIG_DIR/secrets.env"
SETTINGS="$CONFIG_DIR/settings.json"
RECONCILE_CONF="/usr/local/share/claude-feature/bootstrap.env"

# Nothing staged (mcpServers=false at build time) is not an error.
[ -f "$DEFS" ] || exit 0

if ! command -v jq > /dev/null 2>&1; then
    echo "jq not on PATH — skipping Claude bootstrap" >&2
    exit 0
fi

# --- secrets.env -> settings.json env block ----------------------------------
# The shell profile snippet covers plain terminals, but a stdio MCP server does
# not inherit the shell environment and the VS Code extension may not start a
# login shell. Claude Code reads its own `env` block "no matter how Claude was
# launched", so this is the path that actually makes ${VAR} resolve.
if [ -r "$SECRETS" ]; then
    env_json="$(
        grep -vE '^[[:space:]]*(#|$)' "$SECRETS" \
            | jq -R -s 'split("\n")
                        | map(select(test("=")))
                        | map(split("=") | {(.[0] | ltrimstr("export ") | gsub("^\\s+|\\s+$";"")):
                                            (.[1:] | join("="))})
                        | add // {}'
    )"
    if [ -n "$env_json" ] && [ "$env_json" != "null" ]; then
        tmp="$(mktemp)"
        if [ -s "$SETTINGS" ]; then
            jq --argjson e "$env_json" '.env = ((.env // {}) + $e)' "$SETTINGS" > "$tmp"
        else
            jq -n --argjson e "$env_json" '{env: $e}' > "$tmp"
        fi
        # Only replace on success; a jq failure must not truncate live settings.
        if [ -s "$tmp" ]; then
            mv "$tmp" "$SETTINGS"
            chmod 600 "$SETTINGS"
            echo "  env block in settings.json refreshed from secrets.env ($(jq -r '.env | length' "$SETTINGS") vars)"
        else
            rm -f "$tmp"
            echo "  WARNING: could not build env block — settings.json left alone" >&2
        fi
    fi
else
    echo "  no $SECRETS yet — create it (KEY=value per line, chmod 600) for wandb and zotero"
fi

# --- MCP servers -------------------------------------------------------------
if ! command -v claude > /dev/null 2>&1; then
    echo "claude CLI not on PATH — skipping MCP bootstrap" >&2
    exit 0
fi

# User-scope servers live in .claude.json inside the config dir, which is the
# volume. Read them straight from the file: `claude mcp get` prints prose, so
# there is nothing there to compare a definition against.
USER_CONFIG="$CONFIG_DIR/.claude.json"
[ -s "$USER_CONFIG" ] || USER_CONFIG="${HOME:-/home/vscode}/.claude.json"
BACKUP_DIR="$CONFIG_DIR/mcp-backups"

# Staged by install.sh, which is where Feature options are visible; postCreate
# runs with none of them in its environment.
[ -r "$RECONCILE_CONF" ] && . "$RECONCILE_CONF"

echo "Bootstrapping MCP servers at user scope"
newly_added=""

while read -r name; do
    [ -n "$name" ] || continue
    definition="$(jq -c --arg n "$name" '.mcpServers[$n]' "$DEFS")"

    live=""
    if [ -s "$USER_CONFIG" ]; then
        live="$(jq -c --arg n "$name" '.mcpServers[$n] // empty' "$USER_CONFIG" 2> /dev/null)"
    fi

    # Not present at all: a plain first-run add.
    if [ -z "$live" ]; then
        if claude mcp add-json "$name" "$definition" -s user > /dev/null 2>&1; then
            echo "  '$name' added"
            newly_added="$newly_added $name"
        else
            echo "  WARNING: could not add '$name'" >&2
        fi
        continue
    fi

    # Present. Compare canonically — key order and whitespace are not drift.
    if [ "$(printf '%s' "$live" | jq -S -c . 2> /dev/null)" \
       = "$(printf '%s' "$definition" | jq -S -c . 2> /dev/null)" ]; then
        echo "  '$name' already up to date"
        continue
    fi

    # Present but different. Matching on the name alone and skipping here is what
    # stranded the OAuth-era github entry: the definition was corrected in this
    # Feature, every container already had the name, and the fix could never land.
    # The staged definition is the source of truth, so drift is reconciled — but
    # the old entry is kept, because it may be a deliberate local edit.
    if [ "${RECONCILE_MCP:-true}" != "true" ]; then
        echo "  '$name' differs from the staged definition — left as is (reconcileMcp=false)"
        continue
    fi

    mkdir -p "$BACKUP_DIR"
    backup="$BACKUP_DIR/$name.$(date -u +%Y%m%dT%H%M%SZ).json"
    printf '%s\n' "$live" > "$backup"
    chmod 600 "$backup"

    claude mcp remove "$name" -s user > /dev/null 2>&1
    if claude mcp add-json "$name" "$definition" -s user > /dev/null 2>&1; then
        echo "  '$name' reconciled with the staged definition (previous entry: $backup)"
    else
        echo "  WARNING: could not reconcile '$name' — previous entry saved at $backup" >&2
    fi
done < <(jq -r '.mcpServers | keys[]' "$DEFS")

# Every server here authenticates with a ${VAR} from secrets.env; none uses OAuth.
# `claude mcp login` does not work against api.githubcopilot.com/mcp/, which has no
# dynamic client registration — see the note in mcp-servers.json.
if [ -n "$newly_added" ] && [ ! -r "$SECRETS" ]; then
    echo
    echo "  Added:$newly_added — but no $SECRETS exists yet, so their"
    echo "  \${VAR} references resolve to nothing and the servers will fail to"
    echo "  connect. Create it (KEY=value per line, chmod 600) and re-run this script."
fi
