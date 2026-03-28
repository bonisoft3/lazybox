#!/bin/sh
# Get the directory where this script lives
DIR="$(dirname "$(readlink -f "$0")")"

bin=yq_$(uname -s | tr A-Z a-z)_$(uname -m | sed -e 's/x86_64/amd64/; s/aarch64/arm64/')
cp $DIR/yq.toml $DIR/$bin
# Run mise tool-stub with trusted config
"$DIR/.lazybox" trust -y -a -q .
MISE_LOCKED=0 exec "$DIR/.lazybox" tool-stub "$DIR/$bin" "$@"
