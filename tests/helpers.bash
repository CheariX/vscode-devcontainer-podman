# shellcheck shell=bash
# Starts the image under test like the dev container does (runArgs from examples/devcontainer.json,
# the rest from the devcontainer.metadata label), with a throwaway storage volume.

: "${IMG:?set IMG to the image under test}"
: "${DOCKER:=podman}"
: "${EXTRA_RUN_FLAGS:=}"

DEVCONTAINER_SOCK=/tmp/storage-run-1000/podman/podman.sock

start_devcontainer() {
    CTR="bats-$(basename "$BATS_TEST_FILENAME" .bats)-$BATS_ROOT_PID"
    export CTR
    # The device lives in the Podman VM, not on the Mac running bats; NO_TUN=1 only for hosts without it.
    # A bind mount like the label, not --device
    local tun=("--mount=type=bind,source=/dev/net/tun,target=/dev/net/tun")
    [ "${NO_TUN:-}" = 1 ] && tun=()
    # shellcheck disable=SC2086 # EXTRA_RUN_FLAGS is a list of flags
    "$DOCKER" run -d --name "$CTR" --init \
        --userns=keep-id:uid=1000,gid=1000 "${tun[@]}" \
        --security-opt=label=disable --security-opt=unmask=/proc/sys $EXTRA_RUN_FLAGS \
        --mount "type=volume,source=$CTR,target=/home/podman/.local/share/containers" \
        --mount type=tmpfs,target=/tmp \
        -e "DOCKER_HOST=unix://$DEVCONTAINER_SOCK" \
        -v "$BATS_TEST_DIRNAME/fixtures:/fixtures:ro" \
        "$IMG" sleep infinity >/dev/null
}

stop_devcontainer() {
    "$DOCKER" rm -f -t 0 "$CTR" >/dev/null || true
    "$DOCKER" volume rm -f "$CTR" >/dev/null || true
}

# Run a bash snippet inside the dev container as user podman
in_ctr() {
    "$DOCKER" exec -w /tmp "$CTR" bash -c "$1"
}

# Number of processes matching the pgrep -f pattern whose parent does not match it.
# Rootless podman re-execs itself into its user namespace and shell scripts fork subshells,
# so a plain pgrep -c counts some processes twice.
count_toplevel() {
    in_ctr "p=\"\$(pgrep -f '$1')\"; for i in \$p; do echo \"\$p\" | grep -qx \"\$(ps -o ppid= -p \"\$i\" | tr -d ' ')\" || echo \"\$i\"; done | wc -l"
}

has_tun() {
    in_ctr 'test -c /dev/net/tun'
}
