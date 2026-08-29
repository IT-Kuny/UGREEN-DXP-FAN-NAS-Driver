#!/bin/sh
# Build an Alpine Linux APK package for the DKMS driver source.
# Runs inside alpine:3.21. Env: PKGVER
set -eu
: "${PKGVER:?}"
# Alpine package versions: [0-9.] plus _-separated suffixes; sanitize rc/beta suffixes
ALPVER=$(echo "$PKGVER" | sed -E 's/-/./g; s/([0-9])(rc|beta|alpha|pre|p)([0-9]+)/\1_\2\3/g; s/[^0-9a-zA-Z._]//g')

apk add --quiet bash >/dev/null 2>&1 || true
# enable community repo (akms lives there)
echo "https://dl-cdn.alpinelinux.org/alpine/v3.20/community" >> /etc/apk/repositories
apk update --quiet >/dev/null
apk add --quiet akms >/dev/null 2>&1 || true

apk add --quiet git alpine-sdk sudo >/dev/null

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/prepare-payload.sh"

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

su builduser -c 'cd /tmp/aports/ugreen-it87-dkms && abuild checksum >/dev/null && abuild -r'

cp /home/builduser/packages/ugreen-it87-dkms/noarch/*.apk ${OUT_DIR:-/out}/ || \
    cp /home/builduser/packages/*/noarch/*.apk ${OUT_DIR:-/out}/ || true

echo "Built apk:"
ls -la ${OUT_DIR:-/out}/
