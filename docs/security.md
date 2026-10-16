# Security

## Protect your Mac from the workspace

Your project folder is mounted read-write. Anything inside the container can change it: a malicious dependency, a prompt-injected AI agent, or a bad inner image. Some files in it **run code on the Mac**, outside the container:

| Path | Runs on the Mac when … |
|---|---|
| `.devcontainer/` | the container is (re)built: `initializeCommand`, or new `runArgs`/mounts |
| `.vscode/` | you open the folder locally: tasks with `runOn: folderOpen`, settings pointing at executables |
| `.git/hooks/` | you run `git commit` etc. on the Mac |
| `.git/config` | any git command, or VS Code just opening the folder: `core.fsmonitor`, `core.hooksPath`, `core.sshCommand`, filters |

[`examples/devcontainer.json`](../examples/devcontainer.json) mounts these paths **read-only** inside the container:

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
  - Keep tokens out of environment variables in the dev container: inner containers can read `/proc/<pid>/environ` of its processes. Prefer `podman secret`, credential files with mode `0600`, or the credential helpers VS Code forwards.
- `/proc/sys` is writable (`securityOpt: unmask=/proc/sys`), because netavark sets `net.ipv4.ip_forward` for podman networks and compose. The kernel only allows sysctls of network namespaces the writing user namespace owns; all others stay read-only, as without the option.
- The real boundaries are the rootless outer container and the Podman machine VM.
- Podman machine mounts all of `/Users` into the VM by default. Consider sharing only your code directories:

  ```sh
  podman machine init --volume ~/Code:~/Code
  ```

- SELinux: the image currently sets `securityOpt: label=disable`, as the Podman project's guide for Podman in containers does. A confined type (`label=type:container_engine_t` / `label=nested`) is being evaluated.
