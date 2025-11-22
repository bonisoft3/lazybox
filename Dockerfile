ARG BASE_IMG=chainguard/wolfi-base:latest@sha256:deba562a90aa3278104455cf1c34ffa6c6edc6bea20d6b6d731a350e99ddd32a AS devserver

FROM scratch AS scratchy
COPY --from=busybox:1.36.1-musl@sha256:2f9af5cf39068ec3a9e124feceaa11910c511e23a1670dcfdff0bc16793545fb --chmod=0755 /bin/busybox /lazybox/.local/share/lazybox/bin/
ENV PATH=/lazybox/.local/share/lazybox/bin/:/lazybox/.local/bin:
ENV HOME=/lazybox
SHELL [ "/lazybox/.local/share/lazybox/bin/busybox", "sh", "-c" ]
RUN busybox mkdir -p /lazybox/.local/bin/ && busybox --install /lazybox/.local/bin
CMD [ "/lazybox/.local/bin/sh" ]

FROM scratchy AS bbcurl
# Copy static simplified curl and certificates then install full-featured curl
# from soar repos (but we do not use soar itself because it hits github rate limits)
COPY --from=tarampampam/curl@sha256:617b3306349beaacb7ad82bddda8d6876a40c3bad06d7a28981504d230802d7e --chmod=0755 /bin/curl /tmp/curl
COPY --from=tarampampam/curl@sha256:617b3306349beaacb7ad82bddda8d6876a40c3bad06d7a28981504d230802d7e /etc/ssl/certs/ca-certificates.crt /tmp/
RUN mkdir -p /usr/bin && ln -s $(which busybox) /usr/bin/env && chmod 755 /usr/bin/env
COPY lazy-curl.sh /tmp/
RUN	/tmp/curl --cacert /tmp/ca-certificates.crt -fsSL https://github.com/pkgforge/bincache/releases/download/curl%2Fstunnel%2Fcurl%2F8.13.0-$(uname -m)-$(uname -s | tr "[:upper:]" "[:lower:]")/curl -o $HOME/.local/share/lazybox/bin/static-curl && \
    mkdir -p $HOME/.local/share/ca-certificates && mv /tmp/ca-certificates.crt $HOME/.local/share/ca-certificates/ && \
		mv /tmp/lazy-curl.sh $HOME/.local/bin/curl && \
		chmod 755 $HOME/.local/bin/curl $HOME/.local/share/lazybox/bin/static-curl && rm /tmp/curl

FROM bbcurl AS lazybox-builder
ENV MISE_VERSION=2025.10.2
COPY mise.toml mise.lock mise.alpine.lock ./
RUN mkdir -p $HOME/.config/mise/ && \
	mv mise.toml $HOME/.config/mise/config.toml && \
	mv mise.lock $HOME/.config/mise/config.lock && \
	mv mise.alpine.lock $HOME/.config/mise/config.alpine.lock
COPY --chmod=755 lazy-mise.sh ./
RUN mkdir -p /usr/bin/ && test -x /usr/bin/env || ln $HOME/.local/share/lazybox/bin/busybox /usr/bin/env  # need a absolute path shell interpreter
# Trust the mise configuration files and install tools
RUN mv lazy-mise.sh $HOME/.local/share/lazybox/bin/mise
RUN mise trust $HOME/.config/mise/config.toml && \
		cd $HOME/.config/mise && \
    mise install
COPY --chmod=755 lazy-shims.nu lazy-docker.sh ./
RUN $HOME/.local/share/mise/shims/nu ./lazy-shims.nu $HOME/.config/mise/config.toml && \
	  mv ./lazy-docker.sh $HOME/.local/bin/docker && \
    rm ./lazy-shims.nu && rm -rf $HOME/.local/share/mise/installs/ && \
		cp -a $HOME/.config $HOME/.local/bin/ && rm -rf $HOME/.config/mise && \
		mise trust $HOME/.local/bin/.config/mise/ && \
		rm $HOME/.local/bin/mise

FROM ${BASE_IMG:-scratchy} AS lazybox
ARG LAZYBOX_HOME=/lazybox
ENV LAZYBOX_HOME=/lazybox
ENV PATH=$PATH:${LAZYBOX_HOME}/.local/bin/:${LAZYBOX_HOME}/.local/share/lazybox/bin/
COPY --from=lazybox-builder /lazybox ${LAZYBOX_HOME}
RUN test -f /etc/alpine-release && mv ${LAZYBOX_HOME}/.local/bin/.config/mise/config.alpine.lock ${LAZYBOX_HOME}/.local/bin/.config/mise/config.lock || true

FROM lazybox AS nubox
WORKDIR /root
SHELL [ "/lazybox/.local/bin/nu", "-l", "-c" ]
RUN [ '$env.PATH = ($env.PATH | append /root/.local/bin)', '$env.SSL_CERT_FILE = ($env.LAZYBOX_HOME | path join ".local/share/ca-certificates/ca-certificates.crt")' ] |  | save -f ($nu.default-config-dir | path join 'env.nu')
RUN mkdir ($nu.user-autoload-dirs | path join nubox)
RUN '$env.PATH = ($env.PATH | append /root/.local/bin)' | save -f ($nu.user-autoload-dirs | path join nubox/path.nu)
RUN '$env.SSL_CERT_FILE = ($env.LAZYBOX_HOME | path join ".local/share/ca-certificates/ca-certificates.crt")' | save -f ($nu.user-autoload-dirs | path join nubox/ssl.nu)
RUN mise activate nu | save -f ($nu.user-autoload-dirs | path join nubox/mise.nu)
CMD [ "/lazybox/.local/bin/nu", "-l" ]
