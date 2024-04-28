FROM alpine:3.19.1@sha256:c5b1261d6d3e43071626931fc004f70149baeba2c8ec672bd4f27761f8e1ad6b
RUN wget -O /etc/apk/keys/adoptium.rsa.pub https://packages.adoptium.net/artifactory/api/security/keypair/public/repositories/apk && echo 'https://packages.adoptium.net/artifactory/apk/alpine/main' >> /etc/apk/repositories
RUN apk add --no-cache tar yadm neovim ripgrep fd fzf bat zoxide jq yq postgresql firefox podman nodejs-current python3 temurin-21-jdk cargo rust go firefox
RUN corepack enable pnpm && pnpm --help
RUN rm -rf /var/cache/apk/*
CMD ["bash"]
