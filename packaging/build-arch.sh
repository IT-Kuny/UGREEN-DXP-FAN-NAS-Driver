#!/bin/bash
# Build an Arch Linux DKMS package (.pkg.tar.zst). Covers Arch and Arch-based
# distros like Omarchy. Runs inside archlinux:base-devel. Env: PKGVER
set -euo pipefail
: "${PKGVER:?}"
ARCHVER="${PKGVER//-/}"

pacman -Sy --noconfirm --quiet git >/dev/null 2>&1
useradd -m builduser 2>/dev/null || true

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/common.sh"
chmod -R a+rX /tmp/payload
mkdir -p "${OUT_DIR:-/out}" && chmod 777 /out

cat > /tmp/PKGBUILD <<EOF
pkgname=ugreen-it87-dkms
pkgver=${ARCHVER}
pkgrel=1
pkgdesc="UGREEN DXP NAS system fan kernel driver (it87) — DKMS source"
arch=('any')
url="https://github.com/IT-Kuny/UGREEN-DXP-FAN-NAS-Driver"
license=('GPL2')
depends=('dkms')
source=("\$pkgname-\$pkgver.tar.gz")
sha256sums=('SKIP')

package() {
    install -dm755 "\$pkgdir/usr/src/it87-${PKGVER}"
    cp -r /tmp/payload/it87-${PKGVER}/* "\$pkgdir/usr/src/it87-${PKGVER}/"
}
EOF

# Tarball name matching source= entry
tar -C /tmp/payload -czf /tmp/ugreen-it87-dkms-${ARCHVER}.tar.gz it87-${PKGVER}

chown -R builduser /tmp/PKGBUILD /tmp/ugreen-it87-dkms-${ARCHVER}.tar.gz /tmp/payload /out

sudo -u builduser bash -c '
set -e
mkdir -p /tmp/work && cd /tmp/work
cp /tmp/PKGBUILD /tmp/ugreen-it87-dkms-'"${ARCHVER}"'.tar.gz .
makepkg -f --noconfirm --skippgpcheck --nodeps
cp ugreen-it87-dkms-*.pkg.tar.zst ${OUT_DIR:-/out}/
'

echo "Built arch package:"
ls -la ${OUT_DIR:-/out}/
