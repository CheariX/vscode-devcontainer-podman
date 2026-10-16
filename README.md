# vscode-devcontainer-podman

A VS Code dev container with **rootless Podman inside**, for `amd64` and `arm64`. Run containers, `docker compose` and image builds in your dev container without `--privileged`, `sudo` or extra capabilities.

Made for Podman machine on macOS; works on any Linux host with rootless Podman. Docker is not supported (it has no `--userns=keep-id`).

## Quick start

`.devcontainer/devcontainer.json` in your project:

```jsonc
{
  "image": "ghcr.io/chearix/vscode-devcontainer-podman:5.8",
  "runArgs": [ "--userns=keep-id:uid=1000,gid=1000" ]
}
```

Then **Dev Containers: Reopen in Container**. That's all: user, storage volume, Docker API socket and `/dev/net/tun` come with the image. Only `runArgs` cannot, so that line stays in your file.

On a **rootful** Podman machine also add `"--device=/dev/net/tun"` to `runArgs`.

## What you get

- **Podman** with `docker` CLI, `docker compose`, the Docker API socket (Testcontainers, VS Code Container Tools) and `skopeo`. Compose service names, published ports and healthchecks work.
- **Homebrew** owned by you: `brew install` without root. Put project tools in `.devcontainer/Brewfile`, see [examples/devcontainer.json](examples/devcontainer.json).
- CLI tools: `fish` (default terminal), `eza`, `bat`, `fd`, `ripgrep`, `fzf`, `zoxide`, `htop`, `lazygit`, `git-delta`, `jq`, `yq`, `just`, `tldr`.
- Your **dotfiles** (VS Code `dotfiles.repository`) are applied. There is no root, so install software with `brew`, not `apt`/`dnf`.
- Inner images, compose volumes and the Claude Code login survive rebuilds (one volume each per dev container).

## Recommended: protect your Mac

Code in the container can modify your project folder, including files that run code on the Mac (`.devcontainer/`, `.vscode/`, `.git/hooks`, `.git/config`). [examples/devcontainer.json](examples/devcontainer.json) mounts them read-only. Details: [docs/security.md](docs/security.md).

## Good to know

- Inner containers are **not a security boundary** against the dev container. Run inner images you trust as much as your workspace code.
- One level only: inner containers cannot run Podman themselves.
- No `--memory`/`--cpus` limits for inner containers.
- Unused volumes stay after deleting a dev container: `podman volume ls --filter name=podman-storage- --filter name=claude-`.

## Tags

Use `:5.8` (follows Podman 5.8 with monthly Fedora updates). Pin a build with `:5.8.7-YYYYMMDD`. All tags: [docs/reference.md](docs/reference.md#tags).

## More

- [docs/security.md](docs/security.md): security model, read-only mounts and their side effects
- [docs/reference.md](docs/reference.md): volumes, compose and ports, Homebrew, dotfiles, tags
- [docs/development.md](docs/development.md): building and testing this image
