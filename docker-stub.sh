#!/bin/sh
# Get the directory where this script lives
DIR="$(dirname "$(readlink -f "$0")")"

mkdir -p "$HOME/.docker/cli-plugins/"
if [ ! -x "$HOME/.docker/cli-plugins/docker-compose" ]; then
 ln -sf "$DIR/docker-cli-plugin-docker-compose" "$HOME/.docker/cli-plugins/docker-compose"
fi
if [ ! -x "$HOME/.docker/cli-plugins/docker-buildx" ]; then
 ln -sf "$DIR/docker-cli-plugin-docker-buildx" "$HOME/.docker/cli-plugins/docker-buildx"
fi
"$DIR/../libexec/lazy-mise" trust -y -a -q .
exec "$DIR/../libexec/lazy-mise" tool-stub "$DIR/docker.toml" "$@"
