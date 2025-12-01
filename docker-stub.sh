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
# Check for Alpine and prefer musl variant if available
if [ -f /etc/alpine-release ] && [ -f "$DIR/($tool_name).musl.toml" ]; then
    exec mise tool-stub "$DIR/docker.musl.toml" "$@"
else
    exec mise tool-stub "$DIR/docker.toml" "$@"
fi
