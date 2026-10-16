# syntax=docker/dockerfile:1

# Rootless Podman-in-Podman dev container.
# Setup follows the official Podman image (https://github.com/containers/image_build/tree/main/podman),
# but built on plain Fedora: no VOLUME declarations, no sudo, no setuid binaries, no fuse-overlayfs.

# Homebrew formulae preinstalled for the user (space-separated); override with --build-arg
ARG BREW_PACKAGES="lazygit"

# Only the Fedora release is fixed (Dependabot proposes the next one). Everything else is
# fresh on every build: dnf upgrade, latest Homebrew release, latest bottles.
FROM quay.io/fedora/fedora:44
# Honored by BuildKit (CI); Podman ignores SHELL for OCI images and uses /bin/sh (bash on Fedora)
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG BREW_PACKAGES

# container-selinux is excluded like upstream: the container cannot load policy anyway.
# sudo is a protected package in Fedora; fuse-overlayfs must not come in (no /dev/fuse).
# hadolint ignore=DL3041
RUN dnf -y --setopt=install_weak_deps=False upgrade \
    && dnf -y --setopt=install_weak_deps=False --exclude=container-selinux install \
        aardvark-dns \
        crun \
        docker-compose \
        netavark \
        passt \
        podman \
        podman-docker \
        shadow-utils \
        skopeo \
        \
        curl \
        file \
        gcc \
        git-core \
        gzip \
        less \
        make \
        openssh-clients \
        procps-ng \
        tar \
        unzip \
        which \
        \
        bat \
        eza \
        fd-find \
        fish \
        fzf \
        git-delta \
        htop \
        jq \
        just \
        python3-pyyaml \
        ripgrep \
        tealdeer \
        yq \
        zoxide \
    && dnf -y --setopt=protected_packages= remove sudo \
    && ! rpm -q fuse-overlayfs sudo \
    && rpm --setcaps shadow-utils \
    && dnf clean all \
    && rm -rf /var/cache/dnf /var/cache/libdnf5 /var/log/dnf* /etc/machine-id \
    && touch /etc/containers/nodocker \
    && podman --version \
    && /usr/libexec/docker/cli-plugins/docker-compose version \
    && for t in bat eza fd fish fzf delta htop jq just rg tldr yq zoxide; do "$t" --version >/dev/null; done

# User podman (1000:1000) without extra groups. Subordinate ranges cover the 65536 IDs
# an outer rootless container usually has (0..65535), leaving out the user's own ID.
# Only newuidmap/newgidmap keep privileges, as file capabilities; everything else loses setuid/setgid.
RUN useradd -u 1000 -U -m -s /bin/bash podman \
    && printf 'podman:1:999\npodman:1001:64535\n' > /etc/subuid \
    && cp /etc/subuid /etc/subgid \
    && usermod -p '!' root \
    && find / -xdev -perm /6000 -type f -exec chmod ug-s {} + \
    && test -z "$(find / -xdev -perm /6000 -type f)" \
    && getcap /usr/bin/newuidmap | grep -q cap_setuid \
    && getcap /usr/bin/newgidmap | grep -q cap_setgid

COPY --chmod=0644 rootfs/etc/containers/ /etc/containers/
COPY --chmod=0755 rootfs/usr/local/bin/ /usr/local/bin/

# Like upstream: podman must not try to set up a user namespace itself, and buildah RUN steps
# use chroot isolation because nested rootless cannot create the usual namespaces
ENV _CONTAINERS_USERNS_CONFIGURED="" \
    BUILDAH_ISOLATION=chroot

# Homebrew in the default prefix, owned by the user: installs never need root
RUN install -d -o podman -g podman /home/linuxbrew
USER podman
ENV HOMEBREW_PREFIX=/home/linuxbrew/.linuxbrew \
    HOMEBREW_CELLAR=/home/linuxbrew/.linuxbrew/Cellar \
    HOMEBREW_REPOSITORY=/home/linuxbrew/.linuxbrew/Homebrew \
    HOMEBREW_NO_ANALYTICS=1 \
    HOMEBREW_NO_ENV_HINTS=1 \
    PATH=/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:/usr/local/bin:/usr/bin
# Latest stable Homebrew release (what the official installer and `brew update` use too).
# awk reads all of ls-remote's output: `head -n1` would end git with SIGPIPE, which fails under pipefail.
RUN tag="$(git ls-remote --tags --refs --sort=-version:refname https://github.com/Homebrew/brew '[0-9]*' | awk -F/ 'NR == 1 { t = $3 } END { print t }')" \
    && test -n "$tag" \
    && git clone --quiet --branch "$tag" https://github.com/Homebrew/brew "${HOMEBREW_REPOSITORY}" \
    && mkdir -p "${HOMEBREW_PREFIX}/bin" "${HOMEBREW_PREFIX}/Caskroom" \
    && ln -s ../Homebrew/bin/brew "${HOMEBREW_PREFIX}/bin/brew" \
    && brew --version \
    && mkdir -p ~/.local/share/containers ~/.cache ~/.claude

# Separate layer: changing BREW_PACKAGES does not re-clone Homebrew
# hadolint ignore=SC2086
RUN brew install --quiet ${BREW_PACKAGES} \
    && brew list --versions ${BREW_PACKAGES} \
    && brew cleanup --prune=all \
    && rm -rf ~/.cache/Homebrew

# runArgs (--userns=keep-id, --device=/dev/net/tun) cannot live here; see README.
# ${devcontainerId}: one inner storage and one Claude config per dev container (no sharing between projects).
# CLAUDE_CONFIG_DIR moves ~/.claude.json (login) into the volume as well.
# unmask=/proc/sys: netavark sets net.ipv4.ip_forward in the rootless network namespace when it
# creates a bridge network (compose, podman network). New namespaces copy that value from the VM,
# where it is 0 on Podman machine, so netavark has to write it. Only sysctls of network namespaces
# owned by the writing user namespace are writable; everything else still needs root in the VM.
LABEL devcontainer.metadata='[ \
  { "containerUser": "podman", \
    "remoteUser": "podman", \
    "updateRemoteUserUID": false, \
    "init": true, \
    "securityOpt": [ "label=disable", "unmask=/proc/sys" ], \
    "mounts": [ \
      "source=podman-storage-${devcontainerId},target=/home/podman/.local/share/containers,type=volume", \
      "source=claude-${devcontainerId},target=/home/podman/.claude,type=volume", \
      "type=tmpfs,target=/tmp" \
    ], \
    "containerEnv": { \
      "DOCKER_HOST": "unix:///tmp/storage-run-1000/podman/podman.sock", \
      "CLAUDE_CONFIG_DIR": "/home/podman/.claude" \
    }, \
    "postStartCommand": "/usr/local/bin/podman-api-start", \
    "customizations": { "vscode": { "settings": { \
      "terminal.integrated.defaultProfile.linux": "fish" \
    } } } } \
]'

WORKDIR /workspaces
