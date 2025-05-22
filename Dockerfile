# Microsoft offers three different bases for devcontainers. The first is
# ubuntu, whose apt repository is too slow and requires too much fiddling with
# mirrors to achieve a reasonable performance. The second is alpine, which is great
# but unfortunately pkgx.sh does not work with it. Finally, we are left with
# good old debian.
FROM mcr.microsoft.com/devcontainers/base:debian-11
ARG TARGETARCH

ENV DOCKER_CACHE_MOUNT='/root/.dcm'
ENV PKGX_DIR='/root/.dcm/pkgx'
ENV XDG_CACHE_HOME='/root/.dcm/cache'
ENV XDG_DATA_HOME='/root/.dcm/local/share'
ENV TASK_TEMP_DIR='/root/.dcm/task'
ENV SKAFFOLD_CACHE_FILE='/root/.dcm/skaffold/cache'
ENV PATH $PATH:/root/.local/bin
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

RUN curl -Ssf https://pkgx.sh | sh
RUN --mount=type=cache,target=/root/.dcm/ pkgx pkgx@1.5.0 install \
  nushell.sh@0.104.0 just.systems@1.36.0 \
  neovim.io@0.10.1 rg@14.1.0 fd@10.1.0 fzf@054.2 bat@0.24.0 zoxide@0.9.4 jq@1.7.1 \
  skaffold@2.13.2 kind@0.24.0 kubernetes.io/kubectl@1.31.2

# https://cloud.google.com/artifact-registry/docs/docker/authentication#before_you_begin
RUN sudo usermod -a -G docker vscode

# broken directory in ubuntu, removing silences some warnings
RUN rm -rf /usr/lib/jvm/openjdk-21

SHELL [ "/bin/bash", "-c" ]
