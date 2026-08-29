#!/bin/bash
# Shared env for per-distro build scripts (sourced).
export PAYLOAD_DIR=${PAYLOAD_DIR:-/tmp/payload}
export OUT_DIR=${OUT_DIR:-/out}
export MODULE=it87
export PKGNAME=ugreen-it87-dkms
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)
"$SCRIPT_DIR/prepare-payload.sh"
