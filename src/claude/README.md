
# Claude Code workspace (claude)

Persists Claude Code's state in a named volume so auth, MCP servers and per-project chat history survive a rebuild, replays a versioned set of MCP servers into user scope, and installs machine-wide deny rules that keep the agent out of secret files.

## Example Usage

```json
"features": {
    "ghcr.io/The-Mats/devcontainer-features/claude:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| mcpServers | On container create, replay the MCP server definitions bundled with this feature into user scope. Existing servers of the same name are left untouched. | boolean | true |
| denyRules | Install /etc/claude-code/managed-settings.json with deny rules for secret files. Managed settings sit above user and project settings, so no repository can weaken them. | boolean | true |
| shellVars | Comma- or space-separated names from secrets.env to export into interactive shells — only those a command you type actually needs, such as WANDB_API_KEY for `wandb sync` and training runs. Everything else in the file still reaches Claude Code and its MCP servers through the env block of settings.json, and is deliberately kept out of every shell's environment. Empty exports nothing. | string | WANDB_API_KEY |

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

`github` carries **no credential at all** — GitHub's MCP server supports OAuth, so one
`claude mcp login github --no-browser` replaces a long-lived personal access token
with a short-lived, revocable one stored in the volume's credential file. `wandb` and
`zotero` have no OAuth support yet and reference `${VAR}` instead.

### 3. Secrets, in one place, outside every repository

The two `${VAR}` references resolve from `$CLAUDE_CONFIG_DIR/secrets.env` — a file in
the volume, mode `600`, that no repository knows about:

```
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

```shell
# once per machine, inside the container
printf 'WANDB_API_KEY=...\nZOTERO_API_KEY=...\nZOTERO_LIBRARY_ID=...\n' > "$CLAUDE_CONFIG_DIR/secrets.env"
chmod 600 "$CLAUDE_CONFIG_DIR/secrets.env"
claude mcp login github --no-browser     # no key for this one
```

Then rebuild, or re-run `/usr/local/share/claude-feature/bootstrap.sh` to pick the
file up immediately. On a genuinely new machine the volume starts empty, so also
`claude login` once.

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


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/The-Mats/devcontainer-features/blob/main/src/claude/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
