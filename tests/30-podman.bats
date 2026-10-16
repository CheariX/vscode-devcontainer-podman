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

@test "storage: native overlay on the volume, no fuse" {
    run in_ctr 'podman info --format "{{.Store.GraphDriverName}} {{.Store.GraphRoot}}"'
    [ "$output" = "overlay /home/podman/.local/share/containers/storage" ]
    run in_ctr 'podman info --format json | jq -c .store.graphOptions'
    [[ "$output" != *mount_program* ]]
    in_ctr '! test -e /usr/bin/fuse-overlayfs'
}

@test "podman run" {
    in_ctr 'podman run --rm quay.io/libpod/alpine:latest true'
}

@test "podman build" {
    in_ctr 'mkdir -p b && printf "FROM quay.io/libpod/alpine:latest\nRUN echo ok > /ok\n" > b/Containerfile && podman build -q -t bats-build b'
    run in_ctr 'podman run --rm bats-build cat /ok'
    [ "$output" = ok ]
}

@test "podman unshare gives root only inside the user namespace" {
    run in_ctr 'podman unshare id -u'
    [ "$output" = 0 ]
}

@test "inner containers get their own network namespace" {
    has_tun || skip "no /dev/net/tun on this host"
    outer="$(in_ctr 'readlink /proc/self/ns/net')"
    inner="$(in_ctr 'podman run --rm quay.io/libpod/alpine:latest readlink /proc/self/ns/net')"
    [ -n "$inner" ] && [ "$outer" != "$inner" ]
}

@test "bridge network (netavark) works" {
    has_tun || skip "no /dev/net/tun on this host"
    in_ctr 'podman network create bats-net >/dev/null'
    run in_ctr 'podman run --rm --network bats-net quay.io/libpod/alpine:latest echo ok'
    in_ctr 'podman network rm bats-net >/dev/null'
    [ "$output" = ok ]
}

@test "DOCKER_HOST matches podman's socket path" {
    run in_ctr 'podman info --format "unix://{{.Host.RemoteSocket.Path}}"; echo "$DOCKER_HOST"'
    [ "${lines[0]}" = "${lines[1]}" ]
}

@test "API service starts and is idempotent" {
    in_ctr 'podman-api-start && podman-api-start'
    run in_ctr 'curl -sf --unix-socket "${DOCKER_HOST#unix://}" http://d/_ping'
    [ "$output" = OK ]
    run count_toplevel '[p]odman system service'
    [ "$output" = 1 ]
    run count_toplevel '[p]odman-healthcheck-runner'
    [ "$output" = 1 ]
}

@test "healthchecks run without systemd (podman-healthcheck-runner)" {
    in_ctr 'podman-api-start'
    in_ctr 'podman run -d --name bats-hc --health-cmd true --health-interval 1s quay.io/libpod/alpine:latest sleep 60 >/dev/null'
    run in_ctr 'for i in $(seq 20); do s="$(podman inspect -f "{{.State.Health.Status}}" bats-hc)"; [ "$s" = healthy ] && break; sleep 0.5; done; echo "$s"'
    in_ctr 'podman rm -f -t 0 bats-hc >/dev/null'
    [ "$output" = healthy ]
}
