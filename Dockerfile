ARG BASE_IMG=alpine:3.21@sha256:a8560b36e8b8210634f77d9f7f9efd7ffa463e380b75e2e74aff4511df3ef88c

# === Build environment (not shipped) ===
FROM scratch AS scratchy
COPY --from=busybox:1.36.1-musl@sha256:2f9af5cf39068ec3a9e124feceaa11910c511e23a1670dcfdff0bc16793545fb --chmod=0755 /bin/busybox /build/bin/
ENV PATH=/build/shims:/build/bin:/lazybox/bin:/usr/bin
ENV HOME=/build
SHELL [ "/build/bin/busybox", "sh", "-c" ]
RUN busybox --install /build/bin/
RUN mkdir -p /build/shims /build/libexec /lazybox/bin /lazybox/libexec /lazybox/share/ca-certificates /usr/bin /bin
RUN ln -s /build/bin/sh /usr/bin/env
RUN ln -s /build/bin/sh /bin/sh
CMD [ "/bin/sh" ]
SHELL [ "/bin/sh", "-c" ]

FROM scratchy AS bbcurl
ARG TARGETOS
# Download static curl into the output tree and CA certificates
COPY --from=tarampampam/curl@sha256:617b3306349beaacb7ad82bddda8d6876a40c3bad06d7a28981504d230802d7e --chmod=0755 /bin/curl /tmp/curl
COPY --from=tarampampam/curl@sha256:617b3306349beaacb7ad82bddda8d6876a40c3bad06d7a28981504d230802d7e /etc/ssl/certs/ca-certificates.crt /tmp/
RUN /tmp/curl --cacert /tmp/ca-certificates.crt -fsSL https://github.com/pkgforge/bincache/releases/download/curl%2Fstunnel%2Fcurl%2F8.13.0-$(uname -m)-${TARGETOS}/curl -o /lazybox/libexec/static-curl && chmod 755 /lazybox/libexec/static-curl && rm /tmp/curl
RUN mv /tmp/ca-certificates.crt /lazybox/share/ca-certificates/
# Build-time curl shim (uses the output tree's static-curl + certs)
RUN printf '#!/bin/sh\nexport SSL_CERT_FILE=/lazybox/share/ca-certificates/ca-certificates.crt\nexec /lazybox/libexec/static-curl "$@"\n' > /build/shims/curl && chmod +x /build/shims/curl

FROM bbcurl AS lazybox-builder
ENV MISE_VERSION=2026.3.17
# Build-time mise bootstrap (lives in libexec/, works at both build and run time)
COPY --chmod=0755 lazy-mise /lazybox/libexec/lazy-mise
RUN ln -s /lazybox/libexec/lazy-mise /build/shims/mise
# Generate stubs
COPY --chmod=0755 *.nu .
COPY mise.toml .mise.alpine.lock ./
RUN cp .mise.alpine.lock mise.lock
RUN mise -q trust
RUN mise install
RUN mise exec -- nu mise-lazybox.nu -f -o /lazybox/bin/
# Override docker stubs — mise-lazybox.nu generates incorrect bin paths for http: tools
COPY --chmod=0755 docker-stub.sh /lazybox/bin/docker
COPY docker.toml /lazybox/bin/
COPY --chmod=0755 docker-cli-plugin-docker-compose docker-cli-plugin-docker-buildx /lazybox/bin/
COPY docker-cli-plugin-docker-compose.toml docker-cli-plugin-docker-buildx.toml /lazybox/bin/
COPY --chmod=0755 kubectl /lazybox/bin/kubectl
COPY kubectl.toml /lazybox/bin/
COPY --chmod=0755 yq-stub.sh /lazybox/bin/yq
COPY --chmod=0755 mise-stub.sh /lazybox/bin/mise
# Smoke tests — stubs use lazy-mise which downloads mise to /lazybox/libexec/
RUN yq --help
RUN docker compose version
RUN kubectl --help
RUN skaffold version
# Clean up build artifacts — keep only stubs + static-curl + certs
RUN rm -rf /lazybox/libexec/mise /build $HOME/.local/share/mise $HOME/.cache $HOME/.local/bin

# === Final images ===
FROM ${BASE_IMG} AS lazybox
COPY --from=lazybox-builder /lazybox /lazybox
ENV PATH=$PATH:/lazybox/bin

FROM lazybox AS nubox
WORKDIR /root
SHELL [ "/lazybox/bin/nu", "-l", "-c" ]
RUN [ '$env.PATH = ($env.PATH | append /lazybox/bin)' ] | str join "\n" | save -f ($nu.default-config-dir | path join 'env.nu')
RUN mkdir ($nu.user-autoload-dirs | path join nubox)
RUN '$env.PATH = ($env.PATH | append /root/.local/bin)' | save -f ($nu.user-autoload-dirs | path join nubox/path.nu)
RUN '$env.SSL_CERT_FILE = "/lazybox/share/ca-certificates/ca-certificates.crt"' | save -f ($nu.user-autoload-dirs | path join nubox/ssl.nu)
RUN mise activate nu | save -f ($nu.user-autoload-dirs | path join nubox/mise.nu)
# devcontainer wants to extend this image and needs a posix shell
SHELL [ "/bin/sh", "-c" ]
CMD [ "/lazybox/bin/nu", "-l" ]
