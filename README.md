
<center> 

![CI](https://github.com/The-Mats/devcontainer-features/actions/workflows/test.yaml/badge.svg)

</center>

# devcontainer-features

Personal [dev container Features](https://containers.dev/implementors/features/),
published to GHCR. They exist so that a machine's setup — tooling, Claude Code state,
API keys — live in **one place**, rather than as edits scattered across every
repository where multiple users work. Nothing here requires changing a project's
`devcontainer.json`!

Pairs well with my [dotfile](https://github.com/The-Mats/dotfiles) for `zsh`!


> [!IMPORTANT]
>```
>ghcr.io/the-mats/devcontainer-features/workbench:1
>ghcr.io/the-mats/devcontainer-features/claude:1
>```

## Installation

Add them to **VS Code user settings**, not to a project. They then apply to every dev
container you open, and no repository knows they exist:

```jsonc
// ~/.config/Code/User/settings.json
{
    "dev.containers.defaultFeatures": {
        "ghcr.io/the-mats/devcontainer-features/workbench:1": {},
        "ghcr.io/the-mats/devcontainer-features/claude:1": {}
    }
}
```

Per-project use works too, if you want them declared explicitly:

```jsonc
{
    "features": {
        "ghcr.io/the-mats/devcontainer-features/workbench:1": { "packages": "nvtop,htop" },
        "ghcr.io/the-mats/devcontainer-features/claude:1": {}
    }
}
```

### First run on a new machine

The volume starts empty, so three one-time steps inside the container:

```shell
claude login                              # Claude Code itself
claude mcp login github --no-browser      # OAuth; no API key to paste

printf 'WANDB_API_KEY=...\nZOTERO_API_KEY=...\nZOTERO_LIBRARY_ID=...\n' \
    > "$CLAUDE_CONFIG_DIR/secrets.env"
chmod 600 "$CLAUDE_CONFIG_DIR/secrets.env"
/usr/local/share/claude-feature/bootstrap.sh    # or just rebuild
```

Everything above lands in the `claude-config` volume and persists until the volume is
deleted. Editing `secrets.env` later takes the same last step to pick it up.



## Features

### `workbench`

Terminal tooling, and the editor settings that point at it.

| What | Where it lands | How |
|---|---|---|
| `ripgrep`, `zsh` | `/usr/bin/rg`, `/usr/bin/zsh` | always installed — the VS Code settings below hardcode both |
| `nvtop` and anything else | apt | the `packages` option, installed best-effort |
| `gruntfuggly.todo-tree` | VS Code | `customizations.vscode.extensions` |
| todo-tree → ripgrep, zsh terminal profile | VS Code settings | `customizations.vscode.settings` |

### `claude`

Makes Claude Code's state, credentials and MCP servers survive a rebuild and follow
you between projects.

| What | Where it lands | How |
|---|---|---|
| auth, MCP servers, skills, chat history | volume `claude-config` → `/home/vscode/.claude` | `mounts` + `CLAUDE_CONFIG_DIR` |
| per-project chat history | `~/.claude/projects/-workspaces-<repo>/` | keyed by container path, so projects stay separate |
| MCP servers | user scope | `bootstrap.sh` replays `mcp-servers.json` on create |
| GitHub credentials | the volume's credential store | OAuth — **no API key**, one `claude mcp login github` |
| W&B / Zotero keys | `$CLAUDE_CONFIG_DIR/secrets.env`, mode `600` | in the volume, referenced as `${VAR}` |
| …reaching Claude and MCP | `env` block of `settings.json` | generated from `secrets.env` by `bootstrap.sh` |
| …reaching plain terminals | `/etc/profile.d/10-claude-secrets.sh` | exports an **allowlist** (`shellVars`, default `WANDB_API_KEY`) from the same file; also hooked into `bash.bashrc` / `zshrc` |
| deny rules for credential files | `/etc/claude-code/managed-settings.json` | managed tier — no project can weaken them |



> [!WARNING]
>Key safety
>
>- `github` needs no key at all — it authenticates by OAuth, and the token is short-lived and revocable.
> - The two that still need keys live only in `$CLAUDE_CONFIG_DIR/secrets.env`, mode `600`, inside the volume.
> - Deny rules stop Claude's *file tools* from opening credential files. They do **not** remove values from the process environment, where any subprocess can read them.
> - So the things that actually matter: minimum-scope tokens, and rotate anything that has been printed.


### Publishing

`release.yaml` is `workflow_dispatch` — run it from the Actions tab. It publishes each
feature to GHCR, generates `src/<feature>/README.md` (merging `NOTES.md`), and opens a
PR with the docs. Two repository settings are required:

- *Settings → Actions → General → Workflow permissions*: allow Actions to create and
  approve pull requests, or doc generation cannot open its PR.
- Each GHCR package defaults to **private**; mark it public at
  `https://github.com/users/The-Mats/packages/container/devcontainer-features%2F<feature>/settings`.

