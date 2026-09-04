#!/bin/sh
# Build an Alpine Linux APK package for the DKMS driver source.
# Runs inside alpine:3.21. Env: PKGVER
set -eu
: "${PKGVER:?}"
# Alpine package versions: [0-9.] plus _-separated suffixes; sanitize rc/beta suffixes
ALPVER=$(echo "$PKGVER" | sed -E 's/-/./g; s/([0-9])(rc|beta|alpha|pre|p)([0-9]+)/\1_\2\3/g; s/[^0-9a-zA-Z._]//g')

apk add --quiet bash >/dev/null
# enable community repo (akms lives there)
echo "https://dl-cdn.alpinelinux.org/alpine/v3.21/community" >> /etc/apk/repositories
apk update --quiet >/dev/null
apk add --quiet akms >/dev/null

apk add --quiet git alpine-sdk sudo >/dev/null

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PAYLOAD_DIR="${PAYLOAD_DIR:-/tmp/payload}"
bash "$SCRIPT_DIR/prepare-payload.sh"

adduser -D builduser 2>/dev/null || true
addgroup builduser abuild 2>/dev/null || true
mkdir -p "${OUT_DIR:-/out}" && chmod 777 "${OUT_DIR:-/out}"
chmod -R a+rX /tmp/payload

mkdir -p /tmp/aports/ugreen-it87-dkms
cat > /tmp/aports/ugreen-it87-dkms/APKBUILD <<EOF
# Maintainer: IT-Kuny <it-kuny@users.noreply.github.com>
pkgname=ugreen-it87-dkms
pkgver=$ALPVER
pkgrel=0
pkgdesc="UGREEN DXP NAS system fan kernel driver (it87) — DKMS source"
url="https://github.com/IT-Kuny/UGREEN-DXP-FAN-NAS-Driver"
arch="noarch"
license="GPL-2.0-or-later"
depends="akms"
source="\$pkgname-\$pkgver.tar.gz"
options="!check !fakeroot"
sha512sums="SKIP"

package() {
    mkdir -p "\$pkgdir"/usr/src/it87-\$pkgver
    cp -r "\$srcdir"/it87-*/. "\$pkgdir"/usr/src/it87-\$pkgver/
}
EOF

tar -C /tmp/payload -czf /tmp/aports/ugreen-it87-dkms/ugreen-it87-dkms-$ALPVER.tar.gz it87-$PKGVER
chown -R builduser /tmp/aports /tmp/payload "${OUT_DIR:-/out}"

# Local signing key (untrusted, needed for abuild to produce an apk)
su builduser -c 'abuild-keygen -a -n -i >/dev/null 2>&1 || abuild-keygen -a -n >/dev/null'
# abuild-keygen -i fails as non-root; install the pubkey ourselves so the
# repository index step trusts the signature
cp /home/builduser/.abuild/*.rsa.pub /etc/apk/keys/ 2>/dev/null || true

su builduser -c 'cd /tmp/aports/ugreen-it87-dkms && abuild checksum >/dev/null && abuild -r'

apk_file=$(find /home/builduser/packages -name "ugreen-it87-dkms-*.apk" | head -1)
[ -n "$apk_file" ] || { echo "ERROR: apk not found"; exit 1; }
cp "$apk_file" ${OUT_DIR:-/out}/

echo "Built apk:"
ls -la ${OUT_DIR:-/out}/
