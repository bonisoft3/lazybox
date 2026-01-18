#!/usr/bin/env sh
SCRIPT_PATH=$(dirname $(realpath "$0"))
LAZYBOX_HOME="$SCRIPT_PATH/../../.."
MISE_VERSION=2026.1.2
if [ ! -x "$LAZYBOX_HOME/bin/mise" ]; then
	ARCH=$(uname -m | sed 's/x86_64/x64/; s/aarch64/arm64/')
	OS=$(uname -s | tr "[:upper:]" "[:lower:]" | sed 's/darwin/macos/')
	LIBC=
	if [ "linux" = "$OS" ]; then
		LIBC="-musl" # statically linked everywhere
	fi
	mkdir -p $LAZYBOX_HOME/bin/
  curl -fsSL https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/mise-v${MISE_VERSION}-$OS-$ARCH$LIBC -o $LAZYBOX_HOME/bin/mise
	chmod 755 $LAZYBOX_HOME/bin/mise
fi
export SSL_CERT_FILE=$LAZYBOX_HOME/share/ca-certificates/ca-certificates.crt 
export PATH=$LAZYBOX_HOME/bin:$PATH  # real mise first on PATH
exec "$LAZYBOX_HOME/bin/mise" "$@"
