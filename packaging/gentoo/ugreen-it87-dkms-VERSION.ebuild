# Copyright 2026 IT-Kuny
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="UGREEN DXP NAS system fan kernel driver (it87) — DKMS source"
HOMEPAGE="https://github.com/IT-Kuny/UGREEN-DXP-FAN-NAS-Driver"
SRC_URI="https://github.com/IT-Kuny/UGREEN-DXP-FAN-NAS-Driver/releases/download/v${PV}/it87-${PV}-dkms-source.tar.gz"

LICENSE="GPL-2.0-or-later"
SLOT="0"
KEYWORDS="~amd64 ~x86"
IUSE=""

RDEPEND="sys-kernel/dkms"
DEPEND="${RDEPEND}"

S="${WORKDIR}/it87-${PV}"

src_install() {
    insinto "/usr/src/it87-${PV}"
    doins dkms.conf VERSION Makefile it87.c LICENSE
}

pkg_postinst() {
    dkms add -m it87 -v ${PV} || true
    dkms build -m it87 -v ${PV} && dkms install --force -m it87 -v ${PV} || \
        elog "DKMS build deferred — install sys-kernel/linux-headers for your kernel and run: dkms autoinstall"
    modprobe it87 2>/dev/null || true
}

pkg_prerm() {
    dkms remove -m it87 -v ${PV} --all || true
}
