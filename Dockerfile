FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04@sha256:589ff4a08ed51c23f4a021f02769308054e9095a855644bdffa26d59b0380038 as devserver
ARG TARGETARCH
RUN DEBIAN_FRONTEND=noninteractive

RUN curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install linux --init none --no-confirm
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID
# Add user to trusted users
RUN echo "extra-trusted-users = $USERNAME" | sudo tee -a /etc/nix/nix.conf >/dev/null
# Allow the user to use the nix daemon without sudo
RUN usermod -a -G nixbld $USERNAME

COPY nixinstall.sh /tmp/nixinstall.sh
RUN chmod +x /tmp/nixinstall.sh && /tmp/nixinstall.sh 
