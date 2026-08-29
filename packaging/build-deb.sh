#!/bin/bash
# Build a Debian/Ubuntu DKMS source package (.deb).
# Runs inside debian:bookworm-slim. Env: PKGVER
set -euo pipefail
: "${PKGVER:?}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get install -y -qq --no-install-recommends git >/dev/null

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/common.sh"

VENDOR="IT-Kuny"
MAINT="IT-Kuny <https://github.com/IT-Kuny>"
PKG="ugreen-it87-dkms"
DEST="/tmp/$PKG\_$PKGVER\_all"
MODULE=it87

rm -rf "$DEST"
mkdir -p "$DEST/DEBIAN" "$DEST/usr/src" "$DEST/usr/share/doc/$PKG"

cp -r "$PAYLOAD_DIR/$MODULE-$PKGVER" "$DEST/usr/src/"
cp "$PAYLOAD_DIR/$MODULE-$PKGVER/LICENSE" "$DEST/usr/share/doc/$PKG/copyright"

cat > "$DEST/DEBIAN/control" <<EOF
Package: $PKG
Version: $PKGVER
Section: kernel
Priority: optional
Architecture: all
Depends: dkms
Recommends: linux-headers
Maintainer: $MAINT
Homepage: https://github.com/IT-Kuny/UGREEN-DXP-FAN-NAS-Driver
Description: UGREEN DXP NAS system fan kernel driver (it87) — DKMS source
 Out-of-tree it87 hwmon driver with UGREEN NAS OEM chip support
 (DXP2800, DXP4800, DXP8800, iDX6011, DXP2800 GT and others).
 The module is compiled locally against the running kernel via DKMS.
EOF

cat > "$DEST/DEBIAN/postinst" <<EOF
#!/bin/bash
set -e
if command -v dkms >/dev/null 2>&1; then
    dkms add -m $MODULE/$PKGVER || true
    dkms build -m $MODULE/$PKGVER && dkms install --force -m $MODULE/$PKGVER || \
        echo "[postinst] DKMS build/install deferred — install matching kernel headers and run: dkms autoinstall"
    modprobe $MODULE 2>/dev/null || true
fi
EOF

cat > "$DEST/DEBIAN/prerm" <<EOF
#!/bin/bash
set -e
dkms remove -m $MODULE/$PKGVER --all || true
EOF

chmod 755 "$DEST/DEBIAN/postinst" "$DEST/DEBIAN/prerm"

mkdir -p "${OUT_DIR:-/out}"
OUT="${OUT_DIR:-/out}/${PKG}_${PKGVER}_all.deb"
dpkg-deb --build --root-owner-group "$DEST" "$OUT"
echo "Built $OUT"
