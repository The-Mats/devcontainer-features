
# Workbench (workbench)

Terminal tooling and editor wiring for every dev container: ripgrep, zsh, nvtop, and the todo-tree extension pointed at ripgrep.

## Example Usage

```json
"features": {
    "ghcr.io/The-Mats/devcontainer-features/workbench:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| packages | Extra apt packages, comma- or space-separated. Each is installed best-effort: one that is missing from the base image's repositories is reported and skipped rather than failing the build. ripgrep and zsh are always installed because the VS Code settings below depend on them. | string | nvtop |

## Customizations

### VS Code Extensions

- `gruntfuggly.todo-tree`

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


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/The-Mats/devcontainer-features/blob/main/src/workbench/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
