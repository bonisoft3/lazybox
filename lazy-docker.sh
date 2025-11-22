#!/usr/bin/env sh
SCRIPT_PATH=$(dirname $(realpath "$0"))
MISE=$SCRIPT_PATH/../share/lazybox/bin/mise
cd $SCRIPT_PATH
$MISE trust -q $PWD
$MISE x aqua:docker/buildx -- true
$MISE x aqua:docker/compose -- true
$MISE x aqua:docker/cli -- true
cd -
test -d $HOME/.docker/cli-plugins || mkdir -p $HOME/.docker/cli-plugins/
ln -s $($MISE where aqua:docker/buildx)/docker-cli-plugin-docker-buildx $HOME/.docker/cli-plugins/docker-buildx
ln -s $($MISE where aqua:docker/compose)/docker-cli-plugin-docker-compose $HOME/.docker/cli-plugins/docker-compose
exec $MISE x aqua:docker/cli -- docker "$@"
