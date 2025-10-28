#!/bin/sh
mise x aqua:docker/buildx -- true
mise x aqua:docker/compose -- true
test -d $HOME/.docker/cli-plugins || mkdir -p $HOME/.docker/cli-plugins/
ln -s $(mise where aqua:docker/buildx)/docker-cli-plugin-docker-buildx $HOME/.docker/cli-plugins/docker-buildx
ln -s $(mise where aqua:docker/compose)/docker-cli-plugin-docker-compose $HOME/.docker/cli-plugins/docker-compose
exec mise x aqua:docker/cli -- docker "$@"
