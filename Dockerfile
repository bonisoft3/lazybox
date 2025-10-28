ARG BASE_IMG=alpine/curl

FROM --platform=windows ${BASE_IMG} AS lazybox-windows
RUN scoop install mise nu
COPY mise.toml mise.lock ./
RUN mise install

FROM --platform=linux ${BASE_IMG} AS lazybox-linux
ENV MISE_VERSION=2025.10.2
RUN mkdir -p $HOME/.local/bin && touch $HOME/.profile
RUN . $HOME/.profile && echo export PATH=$PATH:$HOME/.local/bin >> $HOME/.profile
RUN . $HOME/.profile && mkdir -p $HOME/.config/mise/
COPY mise.toml mise.lock mise.alpine.lock ./
RUN . $HOME/.profile && \
	mv mise.toml $HOME/.config/mise/config.toml && \
	mv mise.lock $HOME/.config/mise/config.lock && \
	test -f /etc/alpine-release && mv mise.alpine.lock $HOME/.config/mise/config.lock || rm mise.alpine.lock
COPY --chmod=755 lazy-shims.nu lazy-docker.sh lazy-mise.sh ./
# Trust the mise configuration files and install tools
RUN . $HOME/.profile && mv lazy-mise.sh $HOME/.local/bin/lazy-mise && $HOME/.local/bin/lazy-mise --help && \
    mise trust $HOME/.config/mise/config.toml && \
		cd $HOME/.config/mise && \
    mise install && \
    $HOME/.local/share/mise/shims/nu $OLDPWD/lazy-shims.nu $HOME/.config/mise/config.toml && \
		mv $OLDPWD/lazy-docker.sh $HOME/.local/bin/docker && \
    rm $OLDPWD/lazy-shims.nu && rm -rf $HOME/.local/share/mise/installs/ && \
		rm $HOME/.local/bin/mise

FROM lazybox-$TARGETOS AS lazybox

FROM lazybox AS nubox
WORKDIR /root
RUN . $HOME/.profile && nu --help
SHELL [ "/root/.local/share/mise/shims/nu", "-l", "-c" ]
RUN [ '$env.PATH = ($env.PATH | append /root/.local/bin)', '$env.SSL_CERT_FILE = ($env.HOME | path join ".local/share/ca-certificates/ca-certificates.crt")' ] |  | save -f ($nu.default-config-dir | path join 'env.nu')
RUN mkdir ($nu.user-autoload-dirs | path join nubox)
RUN '$env.PATH = ($env.PATH | append /root/.local/bin)' | save -f ($nu.user-autoload-dirs | path join nubox/path.nu)
RUN '$env.SSL_CERT_FILE = ($env.HOME | path join ".local/share/ca-certificates/ca-certificates.crt")' | save -f ($nu.user-autoload-dirs | path join nubox/ssl.nu)
RUN mise activate nu | save -f ($nu.user-autoload-dirs | path join nubox/mise.nu) 
CMD [ "/root/.local/share/mise/shims/nu", "-l" ]
