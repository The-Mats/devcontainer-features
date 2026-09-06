## What it does

Four things that otherwise have to be redone in every repository and on every machine —
without adding a single line to any repository, including other people's.

### 1. State survives a rebuild

A named volume `claude-config` mounts at `/home/vscode/.claude`, and
`CLAUDE_CONFIG_DIR` points at the same path. That second half matters: without it
Claude Code writes `.claude.json` — which holds your **auth token and MCP servers** —
to `~/.claude.json` on the container filesystem, where it dies with the container.
Pointing the variable into the volume puts auth, MCP servers, skills, `history.jsonl`
and per-project chat history in one place.

Per-project separation is preserved. Projects are keyed by their path inside the
container (`~/.claude/projects/-workspaces-<repo>/`), so each repository keeps its own
history — it now simply outlives the container.

The volume name is fixed rather than `${devcontainerId}`, so one identity spans every
project. Swap it for `${devcontainerId}` if you would rather each project be separate.

### 2. MCP servers, versioned, with no keys committed

`mcp-servers.json` ships with the feature and is replayed into **user** scope on
container create. A server that already exists is left alone, so the bootstrap is safe
on every rebuild and safe against an existing volume.

All three authenticate with a `${VAR}` reference. OAuth is not an option for any of
them today: `api.githubcopilot.com/mcp/` does not support dynamic client registration,
which `claude mcp login` requires, so that flow fails with *"Incompatible auth server"*
([claude-code#3433](https://github.com/anthropics/claude-code/issues/3433),
[#3273](https://github.com/anthropics/claude-code/issues/3273)). GitHub's server does
speak OAuth, but only to clients with a pre-registered client ID, which Claude Code is
not. Use a fine-grained PAT with the narrowest scopes you need.

### 3. Secrets, in one place, outside every repository

Every `${VAR}` reference resolves from `$CLAUDE_CONFIG_DIR/secrets.env` — a file in the
volume, mode `600`, that no repository knows about:

```
GITHUB_PERSONAL_ACCESS_TOKEN=...
WANDB_API_KEY=...
ZOTERO_API_KEY=...
ZOTERO_LIBRARY_ID=...
```

It reaches two different consumers, which need two different mechanisms:

| Consumer | Mechanism |
|---|---|
| Claude Code and its MCP servers | `bootstrap.sh` folds the file into the `env` block of `settings.json`, which Claude Code reads *however it was launched* — a stdio MCP server does not inherit the shell environment, and the VS Code extension may not start a login shell |
| Plain terminal (`wandb sync`, training runs) | `/etc/profile.d/10-claude-secrets.sh`, also hooked into `/etc/bash.bashrc` and `/etc/zsh/zshrc` for interactive non-login shells — VS Code's terminal is usually one of those, so for zsh it is the `zshrc` hook doing the work, not the profile snippet |

The shell gets an **allowlist**, not the whole file. `shellVars` defaults to
`WANDB_API_KEY`, because that is the one a command you type actually needs. The zotero
keys are read only by an MCP server that Claude spawns, which receives them through the
`env` block — putting them in front of every process in every terminal would buy
nothing. Widen the option if something else needs shell access.

There is deliberately **no `--env-file` runArg**. Features cannot contribute `runArgs`,
so that approach needs a line in every `devcontainer.json` you open — which is not
something to do to a shared repository for a personal setup.

### 4. Deny rules nothing can weaken

`/etc/claude-code/managed-settings.json` carries deny rules for credential files.
Managed settings sit above user, project and local settings — and above `--settings` —
so no repository you open can relax them, and they apply in a project with no
`.claude/` directory at all.

Paths are absolute on purpose: a relative rule such as `Read(./**/*secret*)` in a
non-project settings file resolves against that file's own directory rather than
against each project, and would silently match nothing.

`settings.json` and `.credentials.json` are denied by name because neither matches
`*secret*`, and both end up holding credentials.

`Bash(printenv*)` is there because nothing else on the system starts with `printenv`,
so it costs nothing. `Bash(env*)` is deliberately absent — it would also match
`envsubst` and `envdir`.

**What these rules do not do:** they stop Claude's *file tools* from opening those
paths, and discourage one way of dumping the environment. They do not remove the
values from the process environment — `echo $VAR`, `set` and `/proc/self/environ` all
sail past. No storage choice changes that; the controls that matter there are
minimum-scope tokens and rotation.

## Setting it up

Write the keys straight into `$CLAUDE_CONFIG_DIR/secrets.env`
(`/home/vscode/.claude/secrets.env`) with an editor — not with a shell heredoc, which
would store every value in `~/.zsh_history`. One `KEY=value` per line:

```ini
GITHUB_PERSONAL_ACCESS_TOKEN=github_pat_...
WANDB_API_KEY=...
ZOTERO_API_KEY=...
ZOTERO_LIBRARY_ID=...
```

Then, in the container:

```shell
chmod 600 "$CLAUDE_CONFIG_DIR/secrets.env"
/usr/local/share/claude-feature/bootstrap.sh   # regenerate the env block
```

Editing `secrets.env` later needs that same last step — or a rebuild — to pick it up.
On a genuinely new machine the volume starts empty, so also `claude login` once.

## Assumptions

Debian-family base image, and a remote user whose home is `/home/vscode`. Feature
metadata takes no option substitution — `mounts` accepts only `${devcontainerId}` — so
the mount target cannot be derived from `$_REMOTE_USER_HOME`. A different home is
warned about at build time and still works, because `CLAUDE_CONFIG_DIR` is what Claude
Code actually reads.

`dependsOn` pulls in `ghcr.io/devcontainers/features/node` as well as the official
`claude-code` feature. Node is not optional padding: on Debian 13 the distro `nodejs`
package ships **without** `npm`, so `claude-code`'s own installer gets Node, fails its
`npm` check, and aborts the whole build. The node feature supplies both, and
`claude-code` already declares `installsAfter` node, so the ordering resolves itself.

## Example

```jsonc
{
    "features": {
        "ghcr.io/the-mats/devcontainer-features/claude:1": {}
    }
}
```
