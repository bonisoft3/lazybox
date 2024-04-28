FROM nixos/nix:2.23.0pre20240424_7e10484
RUN mkdir -p /etc/nix && \
    echo 'experimental-features = nix-command flakes' >> /etc/nix/nix.conf
RUN nix-env -i tar gnused yadm neovim ripgrep fd fzf bat zoxide-unstable jq yq postgresql firefox podman podman-compose  python3 nodejs temurin-bin rustc
RUN corepack enable pnpm && pnpm --help
