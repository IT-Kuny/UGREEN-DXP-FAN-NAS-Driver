#!/bin/bash
# Build a Fedora/RHEL DKMS source package (.rpm, noarch).
# Runs inside fedora:latest. Env: PKGVER
set -euo pipefail
: "${PKGVER:?}"

dnf -y install --quiet rpm-build rpmdevtools git >/dev/null 2>&1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/common.sh"

MODULE=it87
PKG=ugreen-it87-dkms

rpmdev-setuptree
SPEC=~/rpmbuild/SPECS/$PKG.spec
mkdir -p ~/rpmbuild/SPECS

# Vendor the source payload as tarball for the build
TARBALL=~/rpmbuild/SOURCES/$MODULE-$PKGVER.tar.gz
tar -C "$PAYLOAD_DIR" -czf "$TARBALL" $MODULE-$PKGVER

cat > "$SPEC" <<EOF
Name:    $PKG
Version: $PKGVER
Release: 1%{?dist}
Summary: UGREEN DXP NAS system fan kernel driver (it87) — DKMS source
License: GPL-2.0-or-later
URL:     https://github.com/IT-Kuny/UGREEN-DXP-FAN-NAS-Driver
Source0: $MODULE-%{version}.tar.gz
BuildArch: noarch
Requires: dkms
Recommends: kernel-devel

%description
Out-of-tree it87 hwmon driver with UGREEN NAS OEM chip support
(DXP2800, DXP4800, DXP8800, iDX6011, DXP2800 GT and others).
The module is compiled locally against the running kernel via DKMS.

%prep
%setup -q -n $MODULE-%{version}

%build
# nothing to build — DKMS compiles at install time

%install
mkdir -p %{buildroot}/usr/src/$MODULE-%{version}
cp -r dkms.conf VERSION Makefile it87.c LICENSE %{buildroot}/usr/src/$MODULE-%{version}/

%post
if command -v dkms >/dev/null 2>&1; then
    dkms add -m $MODULE -v %{version} || :
    dkms build -m $MODULE -v %{version} && dkms install --force -m $MODULE -v %{version} || \
        echo "[post] DKMS build deferred — install kernel-devel/kernel headers and run: dkms autoinstall"
    modprobe $MODULE 2>/dev/null || :
fi

%preun
dkms remove -m $MODULE -v %{version} --all || :

%files
/usr/src/$MODULE-%{version}/
%license LICENSE

%changelog
* $(date '+%a %b %d %Y') IT-Kuny - $PKGVER-1
- Automated build for release $PKGVER
EOF

mkdir -p "${OUT_DIR:-/out}"
rpmbuild -bb --quiet "$SPEC"
cp ~/rpmbuild/RPMS/noarch/$PKG-$PKGVER-1.*.noarch.rpm "${OUT_DIR:-/out}/${PKG}-${PKGVER}-1.noarch.rpm"
echo "Built rpm for $PKGVER"
ls -la ${OUT_DIR:-/out}/
