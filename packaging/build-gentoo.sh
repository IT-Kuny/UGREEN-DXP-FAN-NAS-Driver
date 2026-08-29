#!/bin/bash
# Assemble the Gentoo ebuild overlay tarball + generic DKMS source tarball.
# Runs on plain ubuntu runner (no container needed). Env: PKGVER
set -euo pipefail
: "${PKGVER:?}"

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/common.sh"

mkdir -p "$OUT_DIR"

# Generic DKMS source tarball (usable on any distro via `dkms add`):
tar -C /tmp/payload -czf "$OUT_DIR/it87-$PKGVER-dkms-source.tar.gz" it87-$PKGVER

# Gentoo overlay
OVERLAY=/tmp/ugreen-it87-overlay
rm -rf "$OVERLAY"
mkdir -p "$OVERLAY"/{metadata,profiles,sys-kernel/ugreen-it87-dkms}

echo 'masters = gentoo' > "$OVERLAY/metadata/layout.conf"
echo 'ugreen-it87' > "$OVERLAY/profiles/repo_name"

cat > "$OVERLAY/sys-kernel/ugreen-it87-dkms/metadata.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE pkgmetadata SYSTEM "https://www.gentoo.org/dtd/metadata.dtd">
<pkgmetadata>
  <maintainer type="project">
    <email>noreply@github.com</email>
    <name>IT-Kuny</name>
  </maintainer>
  <longdescription>UGREEN DXP NAS system fan kernel driver (it87) with UGREEN
  OEM chip support, installed as DKMS source.</longdescription>
</pkgmetadata>
EOF

sed "s/VERSION/$PKGVER/" "$SCRIPT_DIR/gentoo/ugreen-it87-dkms-VERSION.ebuild" \
    > "$OVERLAY/sys-kernel/ugreen-it87-dkms/ugreen-it87-dkms-$PKGVER.ebuild"

tar -C /tmp -czf "$OUT_DIR/ugreen-it87-gentoo-overlay-$PKGVER.tar.gz" ugreen-it87-overlay

echo "Built generic source + gentoo overlay tarballs"
ls -la $OUT_DIR/
