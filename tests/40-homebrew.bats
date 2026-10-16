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

@test "brew installs a bottle without root" {
    in_ctr 'brew install --quiet hello'
    run in_ctr 'hello'
    [ "$output" = "Hello, world!" ]
}
