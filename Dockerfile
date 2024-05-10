FROM gcr.io/google.com/cloudsdktool/google-cloud-cli:474.0.0-alpine@sha256:30af8fbda5f3f330c836c676e1b4dc718230d0db3984205f19b9dae67f239c2c as gcloud
FROM gcr.io/k8s-skaffold/skaffold:v2.11.0@sha256:e10f0a2b236e8f89a97e2c6ecf167278457c4775209394b29bd6a94aa8a95f92 as skaffold
# Alpine is part of the officially supported devcontainer base images. The
# debian and ubuntu ones are just too painful to use due to the slowness
# of apt. If alpine gives too much pain, consider going with SUSE Leap.
FROM mcr.microsoft.com/devcontainers/base:alpine-3.14
ARG TARGETARCH
# We cannot upgrade to alpine 19 yet: https://github.com/nodejs/docker-node/issues/2009
RUN sed -i -e 's/14/18/' /etc/apk/repositories
RUN apk del --no-cache shadow && apk -U upgrade --no-cache && apk add --upgrade -U --no-cache util-linux-login apk-tools
RUN apk add -U --no-cache docker-cli=25.0.5-r0 docker-cli-compose=2.23.3-r2 docker-cli-buildx=0.12.0-r2 kubectl=1.28.4-r2 --repository=http://dl-cdn.alpinelinux.org/alpine/v3.19/community/
RUN apk add -U --no-cache buf mkcert kind --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing/
RUN apk add -U --no-cache yadm neovim ripgrep fd fzf bat zoxide jq yq
RUN apk add --no-cache --virtual .gyp python3 make g++  # https://github.com/nodejs/docker-node/blob/main/docs/BestPractices.md#node-gyp-alpine
RUN apk add -U --no-cache linux-headers  # same as https://github.com/grpc/grpc/issues/26882, but with re2
RUN apk add -U --no-cache cargo go .gyp python3 make g++
RUN apk add -U --no-cache nodejs --repository=http://dl-cdn.alpinelinux.org/alpine/v3.19/main/
RUN apk add -U --no-cache openjdk21-jdk --repository=http://dl-cdn.alpinelinux.org/alpine/v3.19/community/
RUN apk add -U --no-cache pnpm=9.1.0-r0 --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing/
RUN apk add -U --no-cache postgresql firefox
RUN apk add -U --no-cache curl python3 py3-crcmod bash libc6-compat openssh-client git # gcloud dependencies

COPY --from=gcloud /google-cloud-sdk /google-cloud-sdk
ENV PATH $PATH:/google-cloud-sdk/bin
COPY --from=skaffold /usr/bin/skaffold /usr/local/bin/

CMD [ "/bin/bash" ]
