# Development

Opening this repo in VS Code builds the image locally (`initializeCommand`, set `DOCKER=docker` on the host for Docker).

```sh
make build            # build the image (IMG=..., PLATFORM=linux/arm64, DOCKER=docker)
make test IMG=...     # run the bats suite against an image - on the host (Mac/CI), needs bats and podman
make lint             # hadolint + shellcheck
```

The tests start the image with the same flags as the dev container. They have to run on the host, because they need two levels of nesting (see [Limitations](reference.md#limitations)).

Builds set `BUILDAH_FORMAT=docker`, so Podman honors `SHELL` (`pipefail`) like BuildKit in CI.

## CI

[`.github/workflows/publish.yml`](../.github/workflows/publish.yml) builds both architectures, runs the tests against the pushed digest and tags only tested images. Scheduled runs (monthly) rebuild without cache to pick up Fedora and Homebrew updates, and open an issue when `quay.io/fedora/fedora:latest` moves to a newer release than `FROM`.
