# vscode-devcontainer-podman

A VS Code dev container with **rootless Podman inside rootless Podman**, for `amd64` and `arm64`. Built for Podman machine on macOS. It also works on any Linux host with rootless Podman.

- **Podman** (Fedora 44 packages) with `docker` CLI shim, `docker compose` / `podman compose`, the Docker API socket and `skopeo`
- **Homebrew**, owned by the container user: install software without root
- CLI tools: `fish` (default terminal), `eza`, `bat`, `fd`, `ripgrep`, `fzf`, `zoxide`, `htop`, `lazygit`, `git-delta`, `jq`, `yq`, `just`, `tldr`
- No `sudo`, no setuid binaries, no extra capabilities, no `--privileged`, no `/dev/fuse`

## Usage

Create `.devcontainer/devcontainer.json` in your project:

```jsonc
{
  "name": "my-project",
  "image": "ghcr.io/chearix/vscode-devcontainer-podman:5.8",
  "runArgs": [
    "--userns=keep-id:uid=1000,gid=1000",
    "--device=/dev/net/tun"
  ]
}
```

The `runArgs` have to live in your file because the image label cannot carry them. Everything else comes with the image: the user, the storage volume, `/tmp` as tmpfs, `DOCKER_HOST`, and the API service.

### Recommended: protect your Mac from the workspace

Your project folder is mounted read-write. Anything inside the container can change it: a malicious dependency, a prompt-injected AI agent, or a bad inner image. Some files in it **run code on the Mac**, outside the container:

| Path | Runs on the Mac when … |
|---|---|
| `.devcontainer/` | the container is (re)built: `initializeCommand`, or new `runArgs`/mounts |
| `.vscode/` | you open the folder locally: tasks with `runOn: folderOpen`, settings pointing at executables |
| `.git/hooks/` | you run `git commit` etc. on the Mac |
| `.git/config` | any git command, or VS Code just opening the folder: `core.fsmonitor`, `core.hooksPath`, `core.sshCommand`, filters |

[`examples/devcontainer.json`](examples/devcontainer.json) mounts these paths **read-only** inside the container:

```jsonc
  "initializeCommand": "mkdir -p .vscode .git/hooks",
  "mounts": [
    "source=${localWorkspaceFolder}/.devcontainer,target=${containerWorkspaceFolder}/.devcontainer,type=bind,readonly",
    "source=${localWorkspaceFolder}/.vscode,target=${containerWorkspaceFolder}/.vscode,type=bind,readonly",
    "source=${localWorkspaceFolder}/.git/config,target=${containerWorkspaceFolder}/.git/config,type=bind,readonly",
    "source=${localWorkspaceFolder}/.git/hooks,target=${containerWorkspaceFolder}/.git/hooks,type=bind,readonly"
  ]
```

Side effects:

- Commands that write the repository config fail inside the container: `git remote add`, `git config <key>` without `--global`, `git push -u` / `--set-upstream`. Do these on the Mac. `commit`, `pull`, `fetch`, `push origin HEAD` and `~/.gitconfig` work normally.
- If git on the Mac rewrites `.git/config`, the container sees the old file until it restarts.
- The mounts fail if a path is missing, hence the `mkdir`.

Not covered are files you run yourself on the Mac: `Makefile`, `package.json` scripts, `.envrc`. Run project code only in the container. For untrusted repositories use **Dev Containers: Clone Repository in Container Volume**. The code then never touches the Mac.

## Security model

- The user `podman` (uid 1000) cannot become root: there is no `sudo`, root is locked, and there are no setuid binaries.
  - Only `newuidmap`/`newgidmap` keep file capabilities, because nested user namespaces need them. That is also why `no-new-privileges` is not used.
- `podman unshare` and inner containers give root only **inside a child user namespace**, mapped to your own uid. That is intended and harmless.
- **Inner containers are not a security boundary against the dev container.** They share its user namespace and `/proc`, which nested rootless Podman requires. An inner container can see and signal the dev container's processes, such as the VS Code server and AI agents with their tokens. Run inner images you trust as much as the code in your workspace.
- `/proc/sys` is writable (`securityOpt: unmask=/proc/sys`), because netavark sets `net.ipv4.ip_forward` for podman networks and compose. The kernel only allows sysctls of network namespaces the writing user namespace owns; all others stay read-only, as without the option.
- The real boundaries are the rootless outer container and the Podman machine VM.
- Podman machine mounts all of `/Users` into the VM by default. Consider sharing only your code directories:

  ```sh
  podman machine init --volume ~/Code:~/Code
  ```

- SELinux: the image currently sets `securityOpt: label=disable`, as the Podman project's guide for Podman in containers does. A confined type (`label=type:container_engine_t` / `label=nested`) is being evaluated.

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

Inner containers get their own network namespace through pasta, which is why `--device=/dev/net/tun` is needed. So service names, `podman network` and `-p` work as usual. To reach a service from the Mac, publish it (`-p 8080:80` or `ports:` in compose). VS Code then forwards `localhost:8080` to the Mac, or you list it in `forwardPorts`.

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

## Development

Opening this repo in VS Code builds the image locally (`initializeCommand`, set `DOCKER=docker` on the host for Docker).

```sh
make build            # build the image (IMG=..., PLATFORM=linux/arm64, DOCKER=docker)
make test IMG=...     # run the bats suite against an image - on the host (Mac/CI), needs bats and podman
make lint             # hadolint + shellcheck
```

The tests start the image with the same flags as the dev container. They have to run on the host, because they need two levels of nesting (see Limitations).
