#!/usr/bin/env bash
#
# Runs as root during image build.
# https://containers.dev/implementors/features/#invoking-installsh
set -euo pipefail

echo "Activating feature 'claude'"

SHARE_DIR="/usr/local/share/claude-feature"
# Hardcoded because Feature metadata takes no option substitution: `mounts`
# accepts only ${devcontainerId}, so the volume target cannot be derived from
# $_REMOTE_USER_HOME and both must agree on this literal path.
VOLUME_HOME="/home/vscode"
CONFIG_DIR="$VOLUME_HOME/.claude"
PROFILE_SNIPPET="/etc/profile.d/10-claude-secrets.sh"

REMOTE_USER="${_REMOTE_USER:-root}"

if [ "${_REMOTE_USER_HOME:-}" != "$VOLUME_HOME" ]; then
    echo "  WARNING: remoteUser home is '${_REMOTE_USER_HOME:-unset}', but this feature" >&2
    echo "           mounts its volume at $CONFIG_DIR. Claude Code reads" >&2
    echo "           CLAUDE_CONFIG_DIR, which points there, so state still persists —" >&2
    echo "           but it will not be at the user's own home." >&2
fi

# Create the mount point *before* the volume attaches, owned by the user who will
# run Claude Code. Docker seeds a brand-new named volume from whatever sits at the
# target path in the image, ownership included; if the directory does not exist
# yet the volume comes up root-owned and Claude Code cannot write to it.
install -d -o "$REMOTE_USER" -g "$REMOTE_USER" -m 0755 "$CONFIG_DIR"
echo "  prepared $CONFIG_DIR (owner: $REMOTE_USER)"

# --- machine-wide deny rules --------------------------------------------------
# Managed settings sit above user, project and local settings, and above
# --settings, so no repository can weaken them. Paths are absolute (`//`):
# a relative rule in a non-project settings file resolves against that file's own
# directory rather than against each project, and would silently match nothing.
#
# settings.json and .credentials.json are named explicitly because neither
# matches *secret*, and both end up holding credentials — the first from the env
# block bootstrap.sh generates, the second from `claude login`.
#
# `printenv*` is a speed bump against the reflex to dump the environment, not a
# control: `echo $VAR`, `set` and /proc/self/environ all sail past it. It is here
# because nothing else on the system starts with `printenv`, so it costs nothing.
# `env*` is deliberately absent — it would also match envsubst and envdir.
if [ "${DENYRULES:-true}" = "true" ]; then
    install -d -m 0755 /etc/claude-code
    cat > /etc/claude-code/managed-settings.json <<'JSON'
{
    "permissions": {
        "deny": [
            "Read(//**/*secret*)",
            "Read(//**/.env)",
            "Read(//home/vscode/.claude/settings.json)",
            "Read(//home/vscode/.claude/.credentials.json)",
            "Bash(printenv*)"
        ]
    }
}
JSON
    chmod 0644 /etc/claude-code/managed-settings.json
    echo "  installed /etc/claude-code/managed-settings.json"
else
    echo "  denyRules=false — skipping managed settings"
fi

# --- secrets on the shell PATH ------------------------------------------------
# Claude Code reads its own `env` block regardless of how it was launched, but a
# plain terminal does not: `wandb sync` and training runs need these too. Sourcing
# from the volume keeps one file as the source of truth and puts nothing in any
# repository.
SHELL_VARS="$(echo "${SHELLVARS-WANDB_API_KEY}" | tr ',' ' ')"

# An allowlist rather than `set -a; . secrets.env`. Only variables a command you
# type actually needs belong in every shell's environment: WANDB_API_KEY does,
# because `wandb sync` and training runs read it. The zotero keys do not — they
# are read by an MCP server that Claude spawns, and it gets them from the env
# block of settings.json. Sourcing the whole file would put them in front of
# every process in every terminal for no benefit.
#
# Silent by design: any output from here breaks powerlevel10k's instant prompt.
cat > "$PROFILE_SNIPPET" <<EOF
# Installed by the 'claude' dev container Feature.
# Exports the allowlisted subset of \$CLAUDE_CONFIG_DIR/secrets.env, which lives
# in the persistent volume. Everything else in that file is Claude-only.
__cs_file="$CONFIG_DIR/secrets.env"
if [ -r "\$__cs_file" ]; then
    for __cs_var in $SHELL_VARS; do
        __cs_line="\$(grep -E "^[[:space:]]*(export[[:space:]]+)?\${__cs_var}=" "\$__cs_file" 2>/dev/null | tail -n 1)"
        [ -n "\$__cs_line" ] && export "\$__cs_var=\${__cs_line#*=}"
    done
    unset __cs_var __cs_line
fi
unset __cs_file
EOF
echo "  shell allowlist: ${SHELL_VARS:-<none>}"
chmod 0644 "$PROFILE_SNIPPET"

# /etc/profile.d is read by *login* shells only. VS Code's integrated terminal
# usually starts an interactive non-login shell, which reads these instead — so
# for a zsh terminal this hook, not the profile snippet, is the one that works.
#
# zsh may not exist yet at build time: the workbench feature that installs it can
# be ordered after this one, and a dotfiles install script runs later still, at
# container create. Create /etc/zsh/zshrc rather than skipping it, so the hook is
# already in place whenever zsh does arrive.
mkdir -p /etc/zsh
[ -f /etc/zsh/zshrc ] || : > /etc/zsh/zshrc

for rc in /etc/bash.bashrc /etc/zsh/zshrc; do
    [ -f "$rc" ] || continue
    grep -q "$PROFILE_SNIPPET" "$rc" && continue
    printf '\n# Installed by the "claude" dev container Feature.\n[ -r %s ] && . %s\n' \
        "$PROFILE_SNIPPET" "$PROFILE_SNIPPET" >> "$rc"
    echo "  hooked $rc"
done
echo "  installed $PROFILE_SNIPPET"

# --- MCP bootstrap ------------------------------------------------------------
install -d -m 0755 "$SHARE_DIR"

if [ "${MCPSERVERS:-true}" = "true" ]; then
    # jq drives the bootstrap; a dependency of this feature rather than an
    # assumption about the base image.
    if command -v apt-get > /dev/null 2>&1 && ! command -v jq > /dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y && apt-get install -y --no-install-recommends jq
        rm -rf /var/lib/apt/lists/*
    fi
    cp "$(dirname "$0")/mcp-servers.json" "$SHARE_DIR/mcp-servers.json"
    chmod 0644 "$SHARE_DIR/mcp-servers.json"
    echo "  staged $SHARE_DIR/mcp-servers.json"
else
    echo "  mcpServers=false — no definitions staged"
fi

# Feature options are visible here, at build time, and nowhere else: the
# postCreateCommand runs with none of them in its environment. Stage the ones
# bootstrap.sh needs as a file it can source.
cat > "$SHARE_DIR/bootstrap.env" <<EOF
# Written by install.sh from this Feature's options. Sourced by bootstrap.sh.
RECONCILE_MCP=${RECONCILEMCP:-true}
EOF
chmod 0644 "$SHARE_DIR/bootstrap.env"
echo "  reconcileMcp: ${RECONCILEMCP:-true}"

# Always installed: postCreateCommand names it unconditionally, and it exits
# quietly when there is nothing staged to replay.
cp "$(dirname "$0")/bootstrap.sh" "$SHARE_DIR/bootstrap.sh"
chmod 0755 "$SHARE_DIR/bootstrap.sh"

echo "Finished."
