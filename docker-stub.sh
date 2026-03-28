#!/bin/sh
# Get the directory where this script lives
DIR="$(dirname "$(readlink -f "$0")")"

mkdir -p $HOME/.docker/cli-plugins/
if [ ! -x $HOME/.docker/cli-plugins/docker-compose ]; then
 ln -sf $DIR/docker-cli-plugin-docker-compose $HOME/.docker/cli-plugins/docker-compose
fi
if [ ! -x $HOME/.docker/cli-plugins/docker-buildx ]; then
 ln -sf $DIR/docker-cli-plugin-docker-buildx $HOME/.docker/cli-plugins/docker-buildx
fi
# Check for Alpine and prefer musl variant if available
if [ -f /etc/alpine-release ] && [ -f "$DIR/docker.musl.toml" ]; then
    "$DIR/.lazybox" trust -y -a -q .
    MISE_LOCKED=0 exec "$DIR/.lazybox" tool-stub "$DIR/docker.musl.toml" "$@"
else
    "$DIR/.lazybox" trust -y -a -q .
    MISE_LOCKED=0 exec "$DIR/.lazybox" tool-stub "$DIR/docker.toml" "$@"
fi
