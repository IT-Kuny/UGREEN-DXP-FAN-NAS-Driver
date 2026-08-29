#!/bin/bash
# Generate the unRAID plugin file (.plg).
# unRAID has no package manager for kernel modules — plugins build on-device
# against the running unRAID kernel. Env: PKGVER, PLG_BASE_URL
set -euo pipefail
: "${PKGVER:?}"

: "${PLG_BASE_URL:=https://github.com/IT-Kuny/UGREEN-DXP-FAN-NAS-Driver/releases/download/v${PKGVER}}"
OUT_DIR="${OUT_DIR:-/out}"
mkdir -p "$OUT_DIR"

cat > "$OUT_DIR/ugreen-it87.plg" <<EOF
<?xml version="1.0"?>
<PLUGIN name="ugreen-it87" author="IT-Kuny" version="$PKGVER"
  pluginURL="" min="6.12.0">
<CONFLICT />
<SUPPORT>https://github.com/IT-Kuny/UGREEN-DXP-FAN-NAS-Driver/issues</SUPPORT>
<CHANGELOG>
<![CDATA[
v$PKGVER — automated release build
]]>
</CHANGELOG>
<DESCRIPTION>
<![CDATA[
UGREEN DXP NAS system fan driver (it87) for unRAID.
Downloads the driver source, builds the out-of-tree it87 hwmon module
against the running unRAID kernel and loads it.
Supports DXP2800, DXP4800, DXP8800, iDX6011 and DXP2800 GT.
Fan control is handled by the UGREEN-Fan-Control daemon or fancontrol.
]]>
</DESCRIPTION>
<FILE Name="/boot/config/plugins/ugreen-it87/source.txz" URL="$PLG_BASE_URL/it87-$PKGVER-dkms-source.tar.gz" Min="6.12.0">
<HELP>Driver source tarball</HELP>
</FILE>
<FILE Run="/bin/bash">
<INLINE>
<![CDATA[
set -e
SRC="/boot/config/plugins/ugreen-it87/source"
rm -rf "\$SRC" && mkdir -p "\$SRC"
VER="\$(tar -xzOf /boot/config/plugins/ugreen-it87/source.txz --wildcards '*/VERSION' | head -1)"
tar -xzf /boot/config/plugins/ugreen-it87/source.txz -C "\$SRC" --strip-components=1
echo "[ugreen-it87] Building v\$VER for kernel \$(uname -r) ..."
cd "\$SRC"
make clean >/dev/null 2>&1 || true
make -j"\$(nproc)"
make install
depmod -a
modprobe it87 ignore_resource_conflict=1 || true
echo "[ugreen-it87] Loaded. Verify with: sensors | grep -A3 it87"
]]>
</INLINE>
</FILE>
</PLUGIN>
EOF

echo "Built $OUT_DIR/ugreen-it87.plg"
ls -la "$OUT_DIR/"
