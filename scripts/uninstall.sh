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
SP5100_TCO_BLACKLIST="/etc/modprobe.d/sp5100_tco-blacklist.conf"
GRUB_DEFAULT_FILE="/etc/default/grub"

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
systemctl stop fancontrol 2>/dev/null || true
systemctl stop fancontrol-config-guard 2>/dev/null || true
systemctl stop it87-driver 2>/dev/null || true

log "Disabling services..."
systemctl disable fancontrol-config-guard.service 2>/dev/null || true
systemctl disable it87-driver.service 2>/dev/null || true

log "Removing systemd files..."
rm -f /etc/systemd/system/it87-driver.service
rm -f /etc/systemd/system/fancontrol-config-guard.service
rm -f /etc/systemd/system/fancontrol.service.d/ugreen-ordering.conf
# Also clean up the old override.conf name from earlier installations
rm -f /etc/systemd/system/fancontrol.service.d/override.conf
if [ -d /etc/systemd/system/fancontrol.service.d ] && [ -z "$(ls -A /etc/systemd/system/fancontrol.service.d)" ]; then
    rmdir /etc/systemd/system/fancontrol.service.d
fi
systemctl daemon-reload

log "Removing modprobe configuration..."
rm -f /etc/modprobe.d/it87.conf
rm -f /etc/modules-load.d/it87.conf

log "Removing AMD-specific configuration (if present)..."
if [ -f "${SP5100_TCO_BLACKLIST}" ]; then
    rm -f "${SP5100_TCO_BLACKLIST}"
    log "Removed ${SP5100_TCO_BLACKLIST}"
fi

# Remove acpi_enforce_resources=lax from GRUB if we added it.
if [ -f "${GRUB_DEFAULT_FILE}" ] && grep -q "acpi_enforce_resources=lax" "${GRUB_DEFAULT_FILE}"; then
    log "Removing 'acpi_enforce_resources=lax' from ${GRUB_DEFAULT_FILE}..."
    # Three substitution passes to cover every position the parameter may appear:
    #   1. trailing: "quiet splash acpi_enforce_resources=lax"
    #   2. leading:  "acpi_enforce_resources=lax quiet splash"
    #   3. standalone (no adjacent spaces): "acpi_enforce_resources=lax"
    sed -i \
        -e "s| acpi_enforce_resources=lax||g" \
        -e "s|acpi_enforce_resources=lax ||g" \
        -e "s|acpi_enforce_resources=lax||g" \
        "${GRUB_DEFAULT_FILE}"
    if command -v update-grub &>/dev/null; then
        update-grub 2>/dev/null || log "WARNING: update-grub failed — regenerate GRUB config manually."
    elif command -v grub2-mkconfig &>/dev/null; then
        grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || true
    elif command -v grub-mkconfig &>/dev/null; then
        grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || true
    fi
    log "Kernel parameter removed from GRUB configuration"
fi

log "Removing config guard script..."
rm -f /usr/local/sbin/fancontrol-config-guard.sh

log "Removing DKMS driver..."
if cd "$IT87_DIR" 2>/dev/null; then
    make dkms_clean 2>/dev/null || true
fi

log "Unloading module..."
modprobe -r it87 2>/dev/null || true

log ""
log "Uninstallation complete."
log "Note: /etc/fancontrol and /etc/fancontrol.d/ were preserved."
log "Remove them manually if no longer needed."
