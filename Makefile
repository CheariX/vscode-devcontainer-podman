IMG ?= vscode-devcontainer-podman:dev
PLATFORM ?=
# Docker works for building; tests need Podman (keep-id, nested rootless)
DOCKER ?= podman
BATS_FLAGS ?= --timing --print-output-on-failure
# Extra flags for the outer container in tests, e.g. --security-opt=apparmor=unconfined in CI
EXTRA_RUN_FLAGS ?=
export IMG DOCKER EXTRA_RUN_FLAGS

.PHONY: build test check lint

# BUILDAH_FORMAT=docker: Podman then honors SHELL (pipefail) like BuildKit in CI; Docker ignores it
build:
	BUILDAH_FORMAT=docker $(DOCKER) build $(if $(PLATFORM),--platform $(PLATFORM)) -f Containerfile -t $(IMG) .

# test deliberately does not build: CI uses it to test a pulled image by digest.
# Run it on the host (Mac/CI), not inside the dev container: nested Podman supports
# only one level of inner containers, the tests need two. They start the image with the
# same flags as the dev container.
test:
	bats $(BATS_FLAGS) tests

lint:
	hadolint Containerfile
	shellcheck rootfs/usr/local/bin/* tests/helpers.bash

check: build test
