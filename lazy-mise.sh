#!/bin/sh
export MISE_VERSION=2025.10.2
test -e $HOME/.profile && . $HOME/.profile
ARCH=$(uname -m | sed 's/x86_64/x64/; s/aarch64/arm64/')
OS=$(uname -s | tr "[:upper:]" "[:lower:]" | sed 's/darwin/macos/')
LIBC=
if [ "linux" = "$OS" ]; then
	LIBC="-musl" # statically linked everywhere
fi
if [ ! -x $HOME/.local/bin/mise ]; then
  curl -fsSL https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/mise-v${MISE_VERSION}-$OS-$ARCH$LIBC -o $HOME/.local/bin/mise
	chmod 755 $HOME/.local/bin/mise
fi
$HOME/.local/bin/mise "$@"
