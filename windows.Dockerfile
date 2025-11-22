ARG BASE_IMG=mcr.microsoft.com/powershell:lts-windowsservercore-ltsc2022@sha256:4d58db7a0242824875f60449f8ebe482e14c15470b2a9a7ca1bce0172770240c

FROM $WINDOWS AS bbcurl-windows
SHELL ["powershell", "-command"]
RUN Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force; \
    iex \"& {$(irm get.scoop.sh)} -RunAsAdmin\"
ENV PATH="$PATH;C:\Users\ContainerAdministrator\scoop\shims"
RUN scoop install busybox curl

FROM bbcurl-windows as lazybox-windows
RUN scoop install nushell mise
COPY mise.toml mise.lock ./
RUN mise trust .
RUN mise install

FROM lazybox-windows as nubox-windows
