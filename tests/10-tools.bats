#!/usr/bin/env bats

setup_file() {
    load helpers
    start_devcontainer
}

teardown_file() {
    load helpers
    stop_devcontainer
}

setup() {
    load helpers
}

@test "tools are installed" {
    for t in bat brew delta eza fd fish fzf git htop jq just lazygit podman rg skopeo tldr yq zoxide; do
        in_ctr "$t --version >/dev/null" || { echo "missing or broken: $t"; return 1; }
    done
}

@test "docker shim and compose" {
    in_ctr 'docker --version | grep -qi podman'
    in_ctr 'docker compose version'
}

@test "brew is first in PATH" {
    run in_ctr 'echo "$PATH"'
    [[ "$output" == /home/linuxbrew/.linuxbrew/bin:* ]]
}
