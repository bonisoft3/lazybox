# See here for image contents: https://github.com/microsoft/vscode-dev-containers/tree/v0.224.3/containers/codespaces-linux/.devcontainer/base.Dockerfile

FROM mcr.microsoft.com/vscode/devcontainers/universal:2-linux

# ** [Optional] Uncomment this section to install additional packages. **
# USER root
#
#RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
#    && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list \
#    && curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add - \
#    && apt-get update \
#    && apt-get -y install --no-install-recommends apt-transport-https ca-certificates gnupg google-cloud-cli \
#        less libxext6 libxrender1 libxtst6 libfreetype6 libxi6  `# projector` \
#        clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev  `# flutter` \
#    && pip install --upgrade google-api-python-client \
#    && pip install --force-reinstall --no-binary :all: cffi `# https://stackoverflow.com/a/70694565` \
#    && BUF_VERSION=1.3.1 curl -sSL \
#       "https://github.com/bufbuild/buf/releases/download/v1.3.1/buf-$(uname -s)-$(uname -m).tar.gz" | \
#       tar -xvzf - -C /usr/local/ --strip-components 1 \
#    && go install github.com/fullstorydev/grpcurl/cmd/grpcurl@v1.8.6 \
#    && go install github.com/fullstorydev/grpcui/cmd/grpcui@v1.3.0   
#    
#USER codespace
#
#RUN pip3 install projector-installer --user \
#    && projector --accept-license autoinstall --config-name bonitao --ide-name "IntelliJ IDEA Community Edition 2021.3" \
#    && curl -sSL https://redirector.gvt1.com/edgedl/android/studio/ide-zips/2021.1.1.23/android-studio-2021.1.1.23-linux.tar.gz | \
#       tar -xvzf - -C $HOME \
#    && git clone https://github.com/flutter/flutter.git $HOME/flutter -b stable \
#    && $HOME/flutter/bin/flutter precache \

