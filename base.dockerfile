FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04@sha256:589ff4a08ed51c23f4a021f02769308054e9095a855644bdffa26d59b0380038 as devserver
ENV DEBIAN_FRONTEND=noninteractive

RUN sudo curl https://raw.githubusercontent.com/vegardit/fast-apt-mirror.sh/v1/fast-apt-mirror.sh -o /usr/local/bin/fast-apt-mirror.sh
RUN sudo chmod 755 /usr/local/bin/fast-apt-mirror.sh
RUN fast-apt-mirror.sh find --apply
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
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

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get -y install --no-install-recommends \
    docker-ce-cli \
    yadm neovim ripgrep fd-find fzf bat zoxide jq yq mkcert

# broken directory in devcontainer ubuntu base, removing silences some warnings
RUN rm -rf /usr/lib/jvm/openjdk-21

RUN curl -Lo skaffold https://storage.googleapis.com/skaffold/releases/v2.9.0/skaffold-linux-$(dpkg --print-architecture) && \
    sudo install skaffold /usr/local/bin/
