# syntax = devthefuture/dockerfile-x:v1.3.3@sha256:807e3b9a38aa29681f77e3ab54abaadb60e633dc5a5672940bb957613b4f9c82
FROM ./base#devserver as devcontainer
ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get -y install --no-install-recommends \
    yadm neovim ripgrep fd-find fzf bat jq yq mkcert \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
    apt-transport-https ca-certificates gnupg google-cloud-cli \
    kubectl google-cloud-cli google-cloud-sdk-gke-gcloud-auth-plugin \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
    openjdk-21-jdk python3 python3-pip openjdk-21-jdk nodejs rustc rust-clippy cargo build-essential \
    firefox qemu-kvm pulseaudio libqt5webenginewidgets5 \
    postgresql-client \
    yadm neovim ripgrep fd-find fzf bat jq yq mkcert

# https://cloud.google.com/artifact-registry/docs/docker/authentication#before_you_begin
RUN sudo usermod -a -G docker vscode

RUN corepack enable  # installs pnpm
# https://github.com/pnpm/pnpm/issues/4495#issuecomment-1518584959
ENV PNPM_HOME=/usr/local/bin

RUN curl -sSL \
    "https://github.com/bufbuild/buf/releases/download/v1.22.0/buf-Linux-$(uname -m).tar.gz" | \
    tar -xzf - -C /usr/local --strip-components 1

RUN curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-$(dpkg --print-architecture) && \
    chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind
