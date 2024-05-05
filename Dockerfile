FROM gcr.io/google.com/cloudsdktool/google-cloud-cli:474.0.0-alpine as gcloud
FROM mcr.microsoft.com/devcontainers/base:alpine-3.14
ARG TARGETARCH
RUN sed -i -e 's/14/19/' /etc/apk/repositories
RUN apk del --no-cache shadow && apk -U upgrade --no-cache && apk add --upgrade -U --no-cache util-linux-login apk-tools
RUN apk add -U --no-cache docker-cli docker-compose docker-cli-buildx kubectl
RUN apk add --no-cache buf mkcert kind --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing/
RUN apk add -U --no-cache yadm neovim ripgrep fd fzf bat zoxide jq yq
RUN wget -O /etc/apk/keys/adoptium.rsa.pub https://packages.adoptium.net/artifactory/api/security/keypair/public/repositories/apk && echo 'https://packages.adoptium.net/artifactory/apk/alpine/main' >> /etc/apk/repositories
RUN apk add -U --no-cache postgresql firefox python3 nodejs temurin-21-jdk cargo go
RUN apk add -U --no-cache pnpm --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing/
RUN apk add -U --no-cache curl python3 py3-crcmod bash libc6-compat openssh-client git # gcloud dependencies

COPY --from=gcloud /google-cloud-sdk /google-cloud-sdk
ENV PATH $PATH:/google-cloud-sdk/bin

CMD [ "/bin/bash" ]
