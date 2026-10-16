#!/usr/bin/env bats
# The main use case: compose stacks with service names and published ports

bats_require_minimum_version 1.5.0

setup_file() {
    load helpers
    start_devcontainer
    has_tun || skip "no /dev/net/tun on this host"
    in_ctr 'podman-api-start'
    in_ctr 'docker compose -f /fixtures/compose/compose.yaml -p bats up -d --wait'
}

teardown_file() {
    load helpers
    stop_devcontainer
}

setup() {
    load helpers
}

@test "services reach each other by name" {
    # compose prints progress on stderr
    run --separate-stderr in_ctr 'docker compose -f /fixtures/compose/compose.yaml -p bats run --rm client wget -qO- http://web/'
    [ "$output" = hello ]
}

@test "published port is reachable from the dev container" {
    run in_ctr 'curl -sf http://localhost:8080/'
    [ "$output" = hello ]
}
