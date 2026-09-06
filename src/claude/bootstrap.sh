#!/usr/bin/env bash
#
# postCreateCommand for the 'claude' feature. Runs as the remote user, after the
# volume is mounted, so everything it reads and writes is persistent.
set -uo pipefail

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-/home/vscode/.claude}"
DEFS="/usr/local/share/claude-feature/mcp-servers.json"
SECRETS="$CONFIG_DIR/secrets.env"
SETTINGS="$CONFIG_DIR/settings.json"

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

echo "Bootstrapping MCP servers at user scope"
newly_added=""

while read -r name; do
    [ -n "$name" ] || continue
    if claude mcp get "$name" > /dev/null 2>&1; then
        echo "  '$name' already configured — left as is"
        continue
    fi
    definition="$(jq -c --arg n "$name" '.mcpServers[$n]' "$DEFS")"
    if claude mcp add-json "$name" "$definition" -s user > /dev/null 2>&1; then
        echo "  '$name' added"
        newly_added="$newly_added $name"
    else
        echo "  WARNING: could not add '$name'" >&2
    fi
done < <(jq -r '.mcpServers | keys[]' "$DEFS")

# Servers that authenticate by OAuth carry no credential and need one
# interactive login, whose token then lives in the volume like everything else.
for name in $(jq -r '._oauth // [] | .[]' "$DEFS"); do
    case " $newly_added " in
        *" $name "*)
            echo
            echo "  '$name' uses OAuth — no API key needed. Authenticate once with:"
            echo "      claude mcp login $name --no-browser"
            ;;
    esac
done
