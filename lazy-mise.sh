#!/usr/bin/env sh
# Build-time mise bootstrap — downloads mise for the build environment.
# Uses static-curl and CA certs from the /lazybox output tree.
MISE_VERSION=2026.3.5
MISE_BIN=/build/bin/mise
if [ ! -x "$MISE_BIN" ]; then
	ARCH=$(uname -m | sed 's/x86_64/x64/; s/aarch64/arm64/')
	OS=$(uname -s | tr "[:upper:]" "[:lower:]" | sed 's/darwin/macos/')
	LIBC=
	if [ "linux" = "$OS" ]; then
		LIBC="-musl"
	fi
	mkdir -p /build/bin/
	export SSL_CERT_FILE=/lazybox/share/ca-certificates/ca-certificates.crt
	/lazybox/libexec/static-curl -fsSL "https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/mise-v${MISE_VERSION}-$OS-$ARCH$LIBC" -o "$MISE_BIN"
	chmod 755 "$MISE_BIN"
fi
export SSL_CERT_FILE=/lazybox/share/ca-certificates/ca-certificates.crt
exec "$MISE_BIN" "$@"
