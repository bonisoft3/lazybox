ARG BASE_IMG=chainguard/wolfi-base:latest@sha256:9925d3017788558fa8f27e8bb160b791e56202b60c91fbcc5c867de3175986c8

FROM scratch AS scratchy
COPY --from=busybox:1.36.1-musl@sha256:2f9af5cf39068ec3a9e124feceaa11910c511e23a1670dcfdff0bc16793545fb --chmod=0755 /bin/busybox /lazybox/.local/share/lazybox/bin/
ENV PATH=/lazybox/.local/share/lazybox/shims:/lazybox/.local/share/lazybox/stubs:/lazybox/.local/share/lazybox/bin/:/usr/bin
ENV HOME=/lazybox
SHELL [ "/lazybox/.local/share/lazybox/bin/busybox", "sh", "-c" ]
RUN busybox --install $HOME/.local/share/lazybox/bin/
RUN mkdir -p $HOME/.local/share/lazybox/shims/
RUN mkdir -p $HOME/.local/share/lazybox/stubs/
RUN mkdir -p $HOME/.local/share/lazybox/libexec/
RUN mkdir -p /usr/bin/ && ln -s $HOME/.local/share/lazybox/bin/sh /usr/bin/env
RUN mkdir -p /bin/ && ln -s $HOME/.local/share/lazybox/bin/sh /bin/sh
CMD [ "/bin/sh" ]
SHELL [ "/bin/sh", "-c" ]

FROM scratchy AS bbcurl
ARG TARGETOS
# Copy static simplified curl and certificates then install full-featured curl
# from soar repos (but we do not use soar itself because it hits github rate limits)
COPY --from=tarampampam/curl@sha256:617b3306349beaacb7ad82bddda8d6876a40c3bad06d7a28981504d230802d7e --chmod=0755 /bin/curl /tmp/curl
COPY --from=tarampampam/curl@sha256:617b3306349beaacb7ad82bddda8d6876a40c3bad06d7a28981504d230802d7e /etc/ssl/certs/ca-certificates.crt /tmp/
RUN /tmp/curl --cacert /tmp/ca-certificates.crt -fsSL https://github.com/pkgforge/bincache/releases/download/curl%2Fstunnel%2Fcurl%2F8.13.0-$(uname -m)-${TARGETOS}/curl -o $HOME/.local/share/lazybox/libexec/static-curl && chmod 755 $HOME/.local/share/lazybox/libexec/static-curl && rm /tmp/curl
RUN mkdir -p $HOME/.local/share/ca-certificates && mv /tmp/ca-certificates.crt $HOME/.local/share/ca-certificates/
COPY --chmod=0755 env-shim.sh /tmp/
RUN mv /tmp/env-shim.sh $HOME/.local/share/lazybox/shims/curl

FROM bbcurl AS lazybox-builder
ENV MISE_VERSION=2026.3.5
RUN mkdir -p $HOME/.local/bin
COPY lazy-mise.sh .
RUN mv lazy-mise.sh $HOME/.local/share/lazybox/libexec/mise
COPY --chmod=0755 env-shim.sh /tmp/
RUN mv /tmp/env-shim.sh $HOME/.local/share/lazybox/shims/mise
COPY --chmod=0755 *.nu .
COPY mise.toml .mise.alpine.lock ./
RUN cp .mise.alpine.lock mise.lock
RUN mise -q trust
RUN mise install
RUN $HOME/.local/share/mise/shims/nu mise-lazybox.nu -f -o $HOME/.local/share/lazybox/stubs/
# Override docker stubs — mise-lazybox.nu generates incorrect bin paths for http: tools
COPY --chmod=0755 docker-stub.sh $HOME/.local/share/lazybox/stubs/docker
COPY docker.toml docker.musl.toml $HOME/.local/share/lazybox/stubs/
COPY --chmod=0755 docker-cli-plugin-docker-compose docker-cli-plugin-docker-buildx $HOME/.local/share/lazybox/stubs/
COPY docker-cli-plugin-docker-compose.toml docker-cli-plugin-docker-compose.musl.toml docker-cli-plugin-docker-buildx.toml docker-cli-plugin-docker-buildx.musl.toml $HOME/.local/share/lazybox/stubs/
COPY --chmod=0755 kubectl $HOME/.local/share/lazybox/stubs/kubectl
COPY kubectl.toml kubectl.musl.toml $HOME/.local/share/lazybox/stubs/
COPY --chmod=0755 yq-stub.sh $HOME/.local/share/lazybox/stubs/yq
RUN yq --help  # quick test
RUN docker compose version  # quick test
RUN kubectl --help  # quick test
# clean up after tests
RUN rm -rf $HOME/.local/share/mise $HOME/.cache $HOME/.local/bin/mise

FROM ${BASE_IMG:-scratchy} AS lazybox
ARG LAZYBOX_HOME=/lazybox
ENV LAZYBOX_HOME=/lazybox
ENV PATH=$PATH:${LAZYBOX_HOME}/.local/share/lazybox/shims/:${LAZYBOX_HOME}/.local/share/lazybox/stubs/:${LAZYBOX_HOME}/.local/share/lazybox/bin:/usr/bin:/bin
COPY --from=lazybox-builder /lazybox ${LAZYBOX_HOME}
RUN mkdir -p /usr/bin/ && test -x /usr/bin/env || ln $HOME/.local/share/lazybox/bin/busybox /usr/bin/env  # need a absolute path shell interpreter

FROM lazybox AS nubox
WORKDIR /root
SHELL [ "/lazybox/.local/share/lazybox/stubs/nu", "-l", "-c" ]
RUN [ '$env.PATH = ($env.PATH | append /lazybox/.local/share/lazybox/shims)', '$env.SSL_CERT_FILE = ($env.LAZYBOX_HOME | path join ".local/share/ca-certificates/ca-certificates.crt")' ] |  | save -f ($nu.default-config-dir | path join 'env.nu')
RUN mkdir ($nu.user-autoload-dirs | path join nubox)
RUN '$env.PATH = ($env.PATH | append /root/.local/bin)' | save -f ($nu.user-autoload-dirs | path join nubox/path.nu)
RUN '$env.SSL_CERT_FILE = ($env.LAZYBOX_HOME | path join ".local/share/ca-certificates/ca-certificates.crt")' | save -f ($nu.user-autoload-dirs | path join nubox/ssl.nu)
RUN mise activate nu | save -f ($nu.user-autoload-dirs | path join nubox/mise.nu)
# devcontainer wants to extend this image and needs a posix shell
SHELL [ "/bin/sh", "-c" ]
CMD [ "/lazybox/.local/share/lazybox/stubs/nu", "-l" ]
