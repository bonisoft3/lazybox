ARG BASE_IMG=chainguard/wolfi-base
ARG WINDOWS=mcr.microsoft.com/powershell:lts-windowsservercore-ltsc2022@sha256:4d58db7a0242824875f60449f8ebe482e14c15470b2a9a7ca1bce0172770240c

FROM --platform=windows $WINDOWS AS bbcurl-windows
SHELL ["powershell", "-command"]
RUN Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force; \
    iex \"& {$(irm get.scoop.sh)} -RunAsAdmin\"
ENV PATH="$PATH;C:\Users\ContainerAdministrator\scoop\shims"
RUN scoop install busybox curl

FROM ${BASE_IMG:-scratch} AS scratchy
# Copy static busybox, which has only non-ssl wget
COPY --from=busybox:1.36.1-musl@sha256:2f9af5cf39068ec3a9e124feceaa11910c511e23a1670dcfdff0bc16793545fb --chmod=0755 /bin/busybox /busybox
SHELL [ "/busybox", "sh", "-l", "-c" ]
RUN test -d /bin || /busybox mkdir -p /bin/
RUN test -x /bin/sh || /busybox ln /busybox /bin/sh 
RUN /busybox which mkdir || /busybox mkdir -p /usr/local/bin && /busybox --install /usr/local/bin/
SHELL [ "/bin/sh", "-l", "-c" ]
CMD [ "/bin/sh", "-l" ]
ENV PATH=$PATH:/usr/local/bin
RUN /busybox rm /busybox

FROM scratchy AS bbcurl-builder
# Copy static simplified curl and certificates then install full-featured curl
# and busybox from soar repos (but we do not use soar itself because it
# hits github rate limits)
COPY --from=tarampampam/curl@sha256:617b3306349beaacb7ad82bddda8d6876a40c3bad06d7a28981504d230802d7e --chmod=0755 /bin/curl /tmp/curl
COPY --from=tarampampam/curl@sha256:617b3306349beaacb7ad82bddda8d6876a40c3bad06d7a28981504d230802d7e /etc/ssl/certs/ca-certificates.crt /tmp/
ENV HOME=/tmp/bbcurl
RUN mkdir -p /tmp/bbcurl
RUN mkdir -p $HOME/.local/share/ca-certificates && \
    mv /tmp/ca-certificates.crt $HOME/.local/share/ca-certificates/ && \
    mkdir -p $HOME/.local/bin && \
		echo export SSL_CERT_FILE="$HOME/.local/share/ca-certificates/ca-certificates.crt" >> $HOME/.profile && \
    echo export PATH=$PATH:$HOME/.local/bin >> $HOME/.profile && \
		. $HOME/.profile && \
		/tmp/curl -fsSL https://github.com/pkgforge/bincache/releases/download/busybox%2Fnixpkgs%2Fbusybox%2F1.36.1-$(uname -m)-$(uname -s | tr "[:upper:]" "[:lower:]")/busybox -o $HOME/.local/bin/busybox && \
		/tmp/curl -fsSL https://github.com/pkgforge/bincache/releases/download/curl%2Fstunnel%2Fcurl%2F8.13.0-$(uname -m)-$(uname -s | tr "[:upper:]" "[:lower:]")/curl -o $HOME/.local/bin/curl && \
    chmod 755 $HOME/.local/bin/busybox $HOME/.local/bin/curl && \
		$HOME/.local/bin/busybox --install $HOME/.local/bin/ && \
		rm /tmp/curl

FROM --platform=linux ${BASE_IMG:-scratchy} AS bbcurl-linux
COPY --from=bbcurl-builder /tmp/bbcurl/.local/ /tmp/root/.local
RUN mkdir -p $HOME/.local && mv /tmp/root/.local/* $HOME/.local/

FROM bbcurl-$TARGETOS AS bbcurl
