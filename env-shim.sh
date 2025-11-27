#!/usr/bin/env sh
SCRIPT_PATH=$(dirname $(realpath "$0"))
# Use embedded ssl cert in case we are in a scratch image
export SSL_CERT_FILE=${SSL_CERT_FILE:-${LAZYBOX_HOME:-${HOME}}/.local/share/ca-certificates/ca-certificates.crt}
# Mise install will point to $(which mise) and we need to make sure it resolves
# to the true binary, not a shim of the same name.
export PATH=$SCRIPT_PATH/../libexec:$PATH
if [ -e $SCRIPT_PATH/../libexec/static-$(basename $0) ]; then
	# ideal case, we do not overload path
	exec $SCRIPT_PATH/../libexec/static-$(basename $0) "$@"
else 
	# mise must be called with the name mise otherwise it tries to 
	# call a tool based on argv0
	exec $SCRIPT_PATH/../libexec/$(basename $0) "$@"
fi
