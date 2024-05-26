# Microsoft offers three different bases for devcontainers. The first is
# ubuntu, whose apt repository is too slow and requires too much fiddling with
# mirrors to achieve a reasonable performance. The second is alpine, which is great
# but unfortunately pkgx.sh does not work with it. Finally, we are left with
# good old debian.
FROM mcr.microsoft.com/devcontainers/base:debian-11
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive
# Add docker: https://docs.docker.com/engine/install/debian/#install-using-the-repository
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    sudo apt-get -y update && \
    sudo apt-get -y  install ca-certificates curl && \
    sudo install -m 0755 -d /etc/apt/keyrings && \
    sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc && \
    sudo chmod a+r /etc/apt/keyrings/docker.asc && \
    echo \
     "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
     $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
     sudo tee /etc/apt/sources.list.d/docker.list > /dev/null && \
     sudo apt-get -y update && \
     sudo apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    sudo apt-get -y update && \
    sudo apt-get -y install python3-pip
RUN python3 -m pip install vscode-task-runner

# https://cloud.google.com/artifact-registry/docs/docker/authentication#before_you_begin
RUN sudo usermod -a -G docker vscode

# broken directory in ubuntu, removing silences some warnings
RUN rm -rf /usr/lib/jvm/openjdk-21

RUN curl -Ssf https://pkgx.sh | sh
RUN pkgx integrate
RUN pkgx install nushell.sh
RUN pkgx install yadm neovim.io rg fd fzf bat zoxide jq yq
RUN pkgx install skaffold kind kubernetes.io/kubectl
ENV PATH $PATH:/root/.local/bin

SHELL [ "/bin/bash", "-c" ]
