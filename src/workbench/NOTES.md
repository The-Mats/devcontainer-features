## What it does

Installs the terminal tools I expect in every container and wires the editor to them:

| Piece | Why |
|---|---|
| `ripgrep` | search, and the binary `todo-tree` shells out to |
| `zsh` | the shell the terminal profile below selects |
| `nvtop` | GPU utilisation, the `htop` of CUDA boxes (default `packages` value) |
| `gruntfuggly.todo-tree` | surfaces TODO/FIXME, pointed at `/usr/bin/rg` |

## Notes

`ripgrep` and `zsh` install unconditionally. Dev Container Feature metadata takes no
option substitution — only `${devcontainerId}`, and only in `mounts` — so
`customizations.vscode.settings` cannot be made conditional on an option. Since those
settings hardcode `/usr/bin/rg` and a `zsh` terminal profile, the packages behind them
are not negotiable. Everything else goes through `packages`.

Extra packages install best-effort: a name missing from the base image's repositories
is reported and skipped rather than failing the build. `nvtop` in particular lives in
Ubuntu's `universe` component, which not every base image enables.

Debian-family images only.

## Example

```jsonc
{
    "features": {
        "ghcr.io/the-mats/devcontainer-features/workbench:1": {
            "packages": "nvtop,htop,tmux"
        }
    }
}
```
