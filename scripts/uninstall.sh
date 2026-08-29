#!/bin/bash
#
# uninstall.sh
#
# Removes the UGREEN Fan Control setup including DKMS driver,
# systemd services, and modprobe configuration.
# Does NOT remove the fancontrol configuration file.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
IT87_DIR="$REPO_DIR/it87"

log() {
    echo "[uninstall] $*"
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "[uninstall] ERROR: This script must be run as root (use sudo)" >&2
        exit 1
    fi
}

check_root

log "Stopping services..."
systemctl stop ugreen-fan-control.service 2>/dev/null || true
systemctl stop ugreen-it87.service 2>/dev/null || true
systemctl stop fancontrol.service 2>/dev/null || true
systemctl stop fancontrol-config-guard.service 2>/dev/null || true
systemctl stop it87-driver.service 2>/dev/null || true

log "Disabling services..."
systemctl disable ugreen-fan-control.service 2>/dev/null || true
systemctl disable ugreen-it87.service 2>/dev/null || true
systemctl disable fancontrol.service 2>/dev/null || true
systemctl disable fancontrol-config-guard.service 2>/dev/null || true
systemctl disable it87-driver.service 2>/dev/null || true

log "Removing systemd files..."
rm -f /etc/systemd/system/ugreen-fan-control.service
rm -f /etc/systemd/system/ugreen-it87.service
# Clean up legacy service names from earlier installations
rm -f /etc/systemd/system/it87-driver.service
rm -f /etc/systemd/system/fancontrol-config-guard.service
rm -f /etc/systemd/system/fancontrol.service.d/ugreen-ordering.conf
rm -f /etc/systemd/system/fancontrol.service.d/override.conf
if [ -d /etc/systemd/system/fancontrol.service.d ] && [ -z "$(ls -A /etc/systemd/system/fancontrol.service.d)" ]; then
    rmdir /etc/systemd/system/fancontrol.service.d
fi
systemctl daemon-reload

log "Removing modprobe configuration..."
rm -f /etc/modprobe.d/it87.conf
rm -f /etc/modules-load.d/it87.conf

log "Removing scripts..."
rm -f /usr/local/sbin/ugreen-fan-control.sh
# Clean up legacy script name from earlier installations
rm -f /usr/local/sbin/fancontrol-config-guard.sh

log "Removing DKMS driver..."
if cd "$IT87_DIR" 2>/dev/null; then
    make dkms_clean 2>/dev/null || true
fi

log "Unloading module..."
modprobe -r it87 2>/dev/null || true

log ""
log "Uninstallation complete."
log "Note: /etc/ugreen/ was preserved."
log "Remove it manually if no longer needed."
