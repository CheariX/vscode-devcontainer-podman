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

@test "runs as podman (1000) without extra groups" {
    run in_ctr 'id -u; id -G'
    [ "${lines[0]}" = 1000 ]
    [ "${lines[1]}" = 1000 ]
}

@test "no effective capabilities" {
    in_ctr 'grep -qx "CapEff:[[:space:]]*0000000000000000" /proc/self/status'
}

@test "sudo is not installed" {
    in_ctr '! command -v sudo'
}

@test "no setuid/setgid binaries" {
    run in_ctr 'find / -xdev -perm /6000 -type f 2>/dev/null'
    [ -z "$output" ]
}

@test "root account is locked" {
    run "$DOCKER" run --rm --user 0 --entrypoint cut "$IMG" -d: -f2 /etc/shadow
    [[ "${lines[0]}" == '!'* ]]
}

@test "su does not lead to root" {
    run in_ctr 'su -c id root </dev/null'
    [ "$status" -ne 0 ]
}

@test "only newuidmap/newgidmap keep file capabilities" {
    in_ctr 'getcap /usr/bin/newuidmap | grep -q cap_setuid'
    in_ctr 'getcap /usr/bin/newgidmap | grep -q cap_setgid'
}

@test "Homebrew prefix belongs to the user" {
    run in_ctr 'stat -c %u /home/linuxbrew/.linuxbrew /home/linuxbrew/.linuxbrew/Cellar'
    [ "${lines[0]}" = 1000 ]
    [ "${lines[1]}" = 1000 ]
}
