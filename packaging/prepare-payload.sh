#!/bin/bash
# Prepare the DKMS source payload shared by all package builds.
# Env: PKGVER (package version), SRC_DIR (repo checkout dir), OUT payload dir.
set -euo pipefail

: "${PKGVER:?PKGVER must be set}"
SRC_DIR="${SRC_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
PAYLOAD_DIR="${PAYLOAD_DIR:-/tmp/payload}"
MODULE=it87

rm -rf "$PAYLOAD_DIR"
mkdir -p "$PAYLOAD_DIR/$MODULE-$PKGVER"

# dkms.conf: fill in the version (same substitution `make dkms` does)
sed -e "/^PACKAGE_VERSION=/ s|.*|PACKAGE_VERSION=\"$PKGVER\"|" \
    "$SRC_DIR/it87/dkms.conf" > "$PAYLOAD_DIR/$MODULE-$PKGVER/dkms.conf"

echo "$PKGVER" > "$PAYLOAD_DIR/$MODULE-$PKGVER/VERSION"

cp "$SRC_DIR/it87/it87.c" \
   "$SRC_DIR/it87/Makefile" \
   "$SRC_DIR/LICENSE" \
   "$PAYLOAD_DIR/$MODULE-$PKGVER/"

# The Makefile must NOT try to git-describe; freeze the version via VERSION file
# (Makefile already prefers an existing VERSION file).

echo "Payload prepared at $PAYLOAD_DIR/$MODULE-$PKGVER (version $PKGVER)"
