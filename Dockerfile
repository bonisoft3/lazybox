ARG BASE_IMAGE=mcr.microsoft.com/devcontainers/base:debian
FROM $BASE_IMAGE
ENV MISE_VERSION=2025.10.2
ENV SOAR_VERSION=0.8.1

# Copy static curl and certificates to bootstrap soar, then install full-featured curl
COPY --from=tarampampam/curl@sha256:617b3306349beaacb7ad82bddda8d6876a40c3bad06d7a28981504d230802d7e /bin/curl /etc/ssl/certs/ca-certificates.crt /tmp/
RUN chmod +x /tmp/curl && \
    mkdir -p $HOME/.local/share/ca-certificates && \
    mv /tmp/ca-certificates.crt $HOME/.local/share/ca-certificates/ && \
    mkdir -p $HOME/.local/share/soar/bin && \
		mv /tmp/curl $HOME/.local/share/soar/bin && \
    export PATH="$PATH:$HOME/.local/share/soar/bin" && \
    export SSL_CERT_FILE="$HOME/.local/share/ca-certificates/ca-certificates.crt"  && \
    curl -fsSL "https://raw.githubusercontent.com/pkgforge/soar/v${SOAR_VERSION}/install.sh" | sh && \
    $HOME/.local/bin/soar install -y curl && \
    curl -fsSL https://mise.jdx.dev/install.sh | MISE_VERSION=v${MISE_VERSION} sh && \
    rm -rf $HOME/.local/share/soar/repos

RUN mkdir -p $HOME/.config/mise/
COPY mise.toml mise.lock mise.alpine.lock .
RUN mv mise.toml $HOME/.config/mise/config.toml && mv mise.lock $HOME/.config/mise/config.lock
RUN test -f /etc/alpine-release && mv mise.alpine.lock $HOME/.config/mise/config.lock || rm mise.alpine.lock
COPY lazy-shims.nu .

# Trust the mise configuration files and install tools
RUN export PATH="$PATH:$HOME/.local/bin:$HOME/.local/share/soar/bin" && \
    export SSL_CERT_FILE="$HOME/.local/share/ca-certificates/ca-certificates.crt" && \
		export MISE_AQUA_GITHUB_ATTESTATIONS=false && \
		export MISE_PARANOID=false && \
		export MISE_AQUA_COSIGN=false && \
		export MISE_AQUA_SLSA=false && \
		export MISE_AQUA_MINISIGN=false && \
    mise trust $HOME/.config/mise/config.toml && \
		cd $HOME/.config/mise && \
    mise install && \
		ln $(mise where aqua:docker/buildx)/docker-cli-plugin-docker-buildx $(mise where aqua:docker/buildx)/docker-buildx && \
    ln $(mise where aqua:docker/compose)/docker-cli-plugin-docker-compose $(mise where aqua:docker/compose)/docker-compose && \
    $HOME/.local/share/mise/shims/nu $OLDPWD/lazy-shims.nu $HOME/.config/mise/config.toml && \
    rm $OLDPWD/lazy-shims.nu && rm -rf $HOME/.local/share/mise/installs/

# ok to hardcode home, will only fail on non-root alpine
ENV ENV=/root/.ashrc
RUN echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.miserc && \
    echo 'export SSL_CERT_FILE="$HOME/.local/share/ca-certificates/ca-certificates.crt"' >> ~/.miserc && \
    echo 'source $HOME/.miserc' >> ~/.bashrc && \
    echo 'eval "$($HOME/.local/bin/mise activate bash)"' >> ~/.bashrc && \
    echo 'source $HOME/.miserc' >> ~/.zshrc && \
    echo 'eval "$($HOME/.local/bin/mise activate zsh)"' >> ~/.zshrc && \
    echo 'source $HOME/.miserc' >> ~/.ashrc && \
    mkdir -p ~/.config/fish && \
    echo 'source ~/.miserc' >> ~/.config/fish/config.fish && \
    echo 'mise activate fish | source' >> ~/.config/fish/config.fish && \
    mkdir -p ~/.config/nushell && \
    echo 'source-env ~/.miserc' >> ~/.config/nushell/env.nu && \
    echo 'mise activate nu | save -f ~/.mise-activate.nu' >> ~/.config/nushell/config.nu && \
    echo 'source ~/.mise-activate.nu' >> ~/.config/nushell/config.nu
