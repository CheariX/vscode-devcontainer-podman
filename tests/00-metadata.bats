#!/usr/bin/env bats
# VS Code silently ignores an invalid devcontainer.metadata label

setup_file() {
    load helpers
    META="$("$DOCKER" image inspect -f '{{ index .Config.Labels "devcontainer.metadata" }}' "$IMG")"
    export META
}

@test "label is valid JSON" {
    jq -e 'type == "array" and length >= 1' <<<"$META"
}

@test "user is podman" {
    jq -e 'any(.[]; .remoteUser == "podman" and .containerUser == "podman")' <<<"$META"
}

@test "inner storage is one volume per dev container" {
    jq -e 'any(.[].mounts[]?; startswith("source=podman-storage-${devcontainerId},target=/home/podman/.local/share/containers,type=volume"))' <<<"$META"
}

@test "Claude config is one volume per dev container" {
    jq -e 'any(.[].mounts[]?; . == "source=claude-${devcontainerId},target=/home/podman/.claude,type=volume")' <<<"$META"
    jq -e 'any(.[]; .containerEnv.CLAUDE_CONFIG_DIR == "/home/podman/.claude")' <<<"$META"
}

@test "/tmp is a tmpfs (fresh podman runroot on every start)" {
    jq -e 'any(.[].mounts[]?; . == "type=tmpfs,target=/tmp")' <<<"$META"
}

@test "DOCKER_HOST and API service are configured" {
    jq -e 'any(.[]; .containerEnv.DOCKER_HOST == "unix:///tmp/storage-run-1000/podman/podman.sock")' <<<"$META"
    jq -e 'any(.[]; .postStartCommand == "/usr/local/bin/podman-api-start")' <<<"$META"
}

@test "/dev/net/tun is mounted (pasta), so runArgs need only --userns" {
    jq -e 'any(.[].mounts[]?; . == "source=/dev/net/tun,target=/dev/net/tun,type=bind")' <<<"$META"
}

@test "/proc/sys is writable (netavark sets ip_forward for bridge networks)" {
    jq -e 'any(.[]; (.securityOpt // []) | index("unmask=/proc/sys"))' <<<"$META"
}

@test "no privileges requested" {
    jq -e 'all(.[]; (.privileged // false) == false and ((.capAdd // []) | length) == 0)' <<<"$META"
}
