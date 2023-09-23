FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04

RUN curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg

RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends apt-transport-https ca-certificates gnupg software-properties-common \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - \
    && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list \
    && curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add - \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - \
    && sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu jammy stable" \
    && sudo add-apt-repository -y ppa:rmescandon/yq \
    && apt-get update \
    && apt-get -y install --no-install-recommends apt-transport-https ca-certificates gnupg google-cloud-cli \
         kubectl google-cloud-cli \
         python3 python3-pip openjdk-17-jdk nodejs rustc rust-clippy cargo build-essential \
         firefox qemu-kvm pulseaudio libqt5webenginewidgets5 \
         postgresql-client \
         yadm neovim ripgrep fd-find fzf bat zoxide fzf jq yq mkcert

RUN corepack enable  # installs pnpm
# https://github.com/pnpm/pnpm/issues/4495#issuecomment-1518584959
ENV PNPM_HOME=/usr/local/bin

RUN curl -sSL \
    "https://github.com/bufbuild/buf/releases/download/v1.22.0/buf-Linux-x86_64.tar.gz" | \
    tar -xzf - -C /usr/local --strip-components 1

RUN curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.19.0/kind-linux-amd64 && \
    chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind

RUN curl -Lo skaffold https://storage.googleapis.com/skaffold/releases/v2.5.1/skaffold-linux-amd64 && \
    sudo install skaffold /usr/local/bin/
