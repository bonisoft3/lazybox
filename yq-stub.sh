#!/bin/sh
# Get the directory where this script lives
DIR="$(dirname "$(readlink -f "$0")")"


bin=yq_$(uname -s | tr A-Z a-z)_$(uname -m | sed -e 's/x86_64/amd64/; s/aarch64/arm64/')
cp $DIR/yq.toml $DIR/$bin
# Run mise tool-stub with trusted config
mise trust -y -a -q .
exec mise tool-stub "$DIR/$bin" "$@"
