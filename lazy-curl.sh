#!/usr/bin/env sh
SCRIPT_PATH=$(dirname $(realpath "$0"))
cd $SCRIPT_PATH
export SSL_CERT_FILE=${SSL_CERT_FILE:-$HOME/.local/share/ca-certificates/ca-certificates.crt}
$SCRIPT_PATH/../share/lazybox/bin/static-curl "$@"
