# See here for image contents: https://github.com/microsoft/vscode-dev-containers/tree/v0.224.3/containers/codespaces-linux/.devcontainer/base.Dockerfile

FROM mcr.microsoft.com/vscode/devcontainers/universal:1-focal

# ** [Optional] Uncomment this section to install additional packages. **
USER root

RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list \
    && curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add - \
    && apt-get update \
    && apt-get -y install --no-install-recommends apt-transport-https ca-certificates gnupg google-cloud-cli \
    && pip install --upgrade google-api-python-client \
    && pip install --force-reinstall --no-binary :all: cffi # https://stackoverflow.com/a/70694565
    
USER codespace
