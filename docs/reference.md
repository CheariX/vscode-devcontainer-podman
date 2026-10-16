# Reference

## What the image configures

The `devcontainer.metadata` label in the [Containerfile](../Containerfile) sets everything except `runArgs`, which a label cannot carry:

- user `podman` (uid/gid 1000), `init`, `securityOpt` (`label=disable`, `unmask=/proc/sys`)
- mounts: the inner storage and Claude Code volumes, `/tmp` as tmpfs, `/dev/net/tun`
- `DOCKER_HOST`, `CLAUDE_CONFIG_DIR`, `postStartCommand` (API service), fish as VS Code terminal

`--userns=keep-id:uid=1000,gid=1000` maps your Mac user to `podman`, so workspace files belong to you on both sides.

## Inner storage volume

Podman inside the container stores images, layers, containers and compose volumes in `~/.local/share/containers`. The image mounts a named volume there:

```
source=podman-storage-${devcontainerId},target=/home/podman/.local/share/containers,type=volume
```

- **Why a volume at all:** the volume lives on a real filesystem in the VM. That gives native overlay without `/dev/fuse` and fuse-overlayfs, because overlay on top of the container's overlay is not possible. Your inner images also survive a rebuild.
- **Why one per dev container** (`${devcontainerId}`, stable across rebuilds): a shared volume would let projects corrupt each other's database when running at the same time, because each has its own locks. It would also let one project replace images another one uses (`postgres:16` → backdoored) and read its compose volumes and container environment, i.e. secrets.
- **Cleanup:** volumes stay when you delete a dev container.

  ```sh
  podman volume ls --filter name=podman-storage-
  podman volume rm podman-storage-<id>
  ```

  Careful: `podman volume prune` also removes the volumes of currently stopped dev containers.

## Claude Code config volume

`~/.claude` is a named volume per dev container (`claude-${devcontainerId}`), so login, sessions and memory survive a rebuild. `CLAUDE_CONFIG_DIR=/home/podman/.claude` moves `.claude.json` into it too. Projects do not share it, for the same reasons as the inner storage. Cleanup: `podman volume ls --filter name=claude-`.

## Compose, Docker API and ports

`DOCKER_HOST` points at Podman's API socket, which `postStartCommand` starts. `docker compose`, `podman compose`, Testcontainers and the VS Code Container Tools work against it. `postStartCommand` also starts `podman-healthcheck-runner`, which runs container healthchecks: Podman schedules them with systemd timers, which the container does not have. Without it, `docker compose up --wait` and `depends_on: condition: service_healthy` would wait forever.

Inner containers get their own network namespace through pasta, which needs `/dev/net/tun` (the image label mounts it). So service names, `podman network` and `-p` work as usual. To reach a service from the Mac, publish it (`-p 8080:80` or `ports:` in compose). VS Code then forwards `localhost:8080` to the Mac, or you list it in `forwardPorts`.

## Homebrew

Homebrew lives in `/home/linuxbrew/.linuxbrew` and belongs to the container user, so `brew install <formula>` needs no root. Installed formulae survive restarts but **not rebuilds**. Keep project tools in a `Brewfile`:

```jsonc
  "postCreateCommand": "test ! -f .devcontainer/Brewfile || brew bundle --file .devcontainer/Brewfile"
```

Homebrew's `bin` comes first in `PATH`, so brew versions shadow the system ones (e.g. a brew `python3`).

## Dotfiles

VS Code's `dotfiles.repository` setting works (also `dotfiles.installCommand` and `dotfiles.targetPath`). After the container is created, the repository is cloned to `~/dotfiles`. Then your `install.sh` (or `setup.sh`, `bootstrap`, …) runs as user `podman`. Without such a script, the dotfiles are symlinked into `~`.

- There is no root, so `sudo apt/dnf install` in your install script fails. Use `brew install` there; `brew` is on `PATH`.
- fish is the VS Code terminal and reads `~/.config/fish/`, but the login shell is bash. Link both configs if you use both.
- Private repositories: an HTTPS URL uses the git credentials VS Code forwards. An SSH URL needs a running `ssh-agent` on the Mac.
- Dotfiles are applied on every container creation, so they come back after a rebuild.

## Tags

| Tag | Moves? | Use |
|---|---|---|
| `:5.8` | within Podman 5.8 | recommended |
| `:5.8.7` | with rebuilds of that Podman version | |
| `:5.8.7-YYYYMMDD` | no | pin a specific build / roll back |
| `:latest`, `:main` | yes | latest build |
| `:sha-<commit>` | no | build of a specific commit |

Images are rebuilt monthly (Fedora security updates) and only tagged after the test suite has passed on both architectures. They come with SBOM and provenance attestations.

## Limitations

- **One level of inner containers.** A dev container can run containers, but those cannot run nested Podman themselves: they reuse the dev container's `/proc`, so `newuidmap` cannot find their processes.
- Inner containers have no own cgroup (no `--memory`/`--cpus` limits) and share IPC/UTS with the dev container.
