FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04@sha256:589ff4a08ed51c23f4a021f02769308054e9095a855644bdffa26d59b0380038 as devserver

RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends apt-transport-https ca-certificates gnupg software-properties-common \
    && curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker.gpg \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/nodesource.gpg \
    && echo "deb [arch=\"$(dpkg --print-architecture)\" signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list \
    && echo  "deb [arch=\"$(dpkg --print-architecture)\" signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \"$(. /etc/os-release && echo $VERSION_CODENAME)\" stable" | sudo tee -a /etc/apt/sources.list.d/docker.list \
    &&  echo "deb [arch=\"$(dpkg --print-architecture)\" signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \"$(. /etc/os-release && echo $VERSION_CODENAME)\" stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && echo  "deb [arch=\"$(dpkg --print-architecture)\" signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" | sudo tee -a /etc/apt/sources.list.d/docker.list \
    && add-apt-repository -y ppa:rmescandon/yq \
    && apt-get update

RUN apt-get -y install --no-install-recommends apt-transport-https ca-certificates gnupg google-cloud-cli \
         kubectl google-cloud-cli google-cloud-sdk-gke-gcloud-auth-plugin \
         python3 python3-pip openjdk-21-jdk nodejs rustc rust-clippy cargo build-essential \
         firefox qemu-kvm pulseaudio libqt5webenginewidgets5 \
         postgresql-client \
         docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
         yadm neovim ripgrep fd-find fzf bat zoxide jq yq mkcert

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

RUN curl -Lo skaffold https://storage.googleapis.com/skaffold/releases/v2.9.0/skaffold-linux-$(dpkg --print-architecture) && \
    sudo install skaffold /usr/local/bin/
