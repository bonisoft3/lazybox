FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04

RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list \
    && curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add - \
    && apt-get update \
    && apt-get -y install --no-install-recommends apt-transport-https ca-certificates gnupg google-cloud-cli \
         firefox qemu-kvm pulseaudio libqt5webenginewidgets5 \
         postgresql-client \
         neovim ripgrep fd-find fzf bat

RUN curl -sSL \ 
    "https://github.com/bufbuild/buf/releases/download/v1.9.0/buf-Linux-x86_64.tar.gz" | \
    tar -xzf - -C /usr/local --strip-components 1
