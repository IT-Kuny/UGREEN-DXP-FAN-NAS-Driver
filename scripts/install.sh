#!/bin/bash
#
# install.sh
#
# Automated installation script for UGREEN Fan Control.
# Builds and installs the it87 driver via DKMS, sets up systemd services
# for reliable driver loading and configuration protection.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
IT87_DIR="$REPO_DIR/it87"
HWMON_VID_MODULE="hwmon-vid"
HWMON_VID_MODULE_ALIAS="hwmon_vid"
HWMON_VID_BUILTIN_PATTERN='(^|/)hwmon[-_]vid(\.ko)?$'

log() {
    echo "[install] $*"
}

error() {
    echo "[install] ERROR: $*" >&2
    exit 1
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root (use sudo)"
    fi
}

is_hwmon_vid_builtin() {
    local kernel_version="${1:-$(uname -r)}"
    local builtin_file="/lib/modules/${kernel_version}/modules.builtin"
    [ -f "$builtin_file" ] && grep -Eq "$HWMON_VID_BUILTIN_PATTERN" "$builtin_file"
}

check_dependencies() {
    log "Checking dependencies..."
    local missing=()

    for cmd in make gcc dkms depmod modprobe git; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing required commands: ${missing[*]}
Please install the required packages:
  Fedora/RHEL: sudo dnf install gcc make dkms dwarves kernel-headers lm_sensors git
  Debian/Ubuntu: sudo apt install gcc make dkms dwarves linux-headers-\$(uname -r) lm-sensors git
  Arch: sudo pacman -S gcc make dkms linux-headers lm_sensors git"
    fi

    # Check for kernel headers
    local kernel_version
    kernel_version=$(uname -r)
    if [ ! -d "/usr/src/linux-headers-${kernel_version}" ] && \
       [ ! -d "/usr/src/kernels/${kernel_version}" ] && \
       [ ! -d "/lib/modules/${kernel_version}/build" ]; then
        error "Kernel headers not found for ${kernel_version}
Please install them:
  Fedora/RHEL: sudo dnf install kernel-headers kernel-devel
  Debian/Ubuntu: sudo apt install linux-headers-${kernel_version}
  Arch: sudo pacman -S linux-headers"
    fi

    log "All dependencies satisfied"
}

check_hwmon_vid() {
    log "Checking ${HWMON_VID_MODULE} availability..."
    local kernel_version
    kernel_version=$(uname -r)

    if ! command -v modinfo &>/dev/null; then
        error "Missing required command: modinfo (usually provided by the 'kmod' package)"
    fi

    if modinfo -k "$kernel_version" "$HWMON_VID_MODULE" &>/dev/null || \
       modinfo -k "$kernel_version" "$HWMON_VID_MODULE_ALIAS" &>/dev/null; then
        log "${HWMON_VID_MODULE} module is available (alias ${HWMON_VID_MODULE_ALIAS} is equivalent)"
        return
    fi

    if is_hwmon_vid_builtin "$kernel_version"; then
        log "${HWMON_VID_MODULE} is built into this kernel"
        return
    fi

    error "$(cat <<EOF
Required dependency '${HWMON_VID_MODULE}' is not available for kernel ${kernel_version}.
This installation was aborted to avoid a broken setup.
Install a kernel package/config that provides ${HWMON_VID_MODULE}, then run this installer again.
EOF
)"
}

check_submodule() {
    if [ ! -f "$IT87_DIR/it87.c" ]; then
        # Run git operations as the invoking user (not root) to avoid leaving
        # the working tree and .git/modules owned by root.
        log "Initializing it87 submodule..."
        cd "$REPO_DIR"
        if [ -n "${SUDO_USER:-}" ]; then
            sudo -u "$SUDO_USER" git submodule init
            sudo -u "$SUDO_USER" git submodule update
        else
            git submodule init
            git submodule update
        fi
    fi

    if [ ! -f "$IT87_DIR/it87.c" ]; then
        error "it87 driver source not found. Please run: git submodule update --init"
    fi
}

install_dkms() {
    log "Building and installing it87 driver via DKMS..."
    cd "$IT87_DIR"

    # Handle BTF generation issue
    local kernel_version
    kernel_version=$(uname -r)
    local build_dir
    build_dir=$(readlink -f "/lib/modules/${kernel_version}/build" 2>/dev/null || echo "/lib/modules/${kernel_version}/build")
    if [ ! -f "${build_dir}/vmlinux" ] && \
       [ -f "/sys/kernel/btf/vmlinux" ]; then
        log "Copying vmlinux for BTF generation..."
        cp /sys/kernel/btf/vmlinux "${build_dir}/" 2>/dev/null || true
    fi

    # Clean up any previous DKMS installation of it87
    local existing_versions
    existing_versions=$(dkms status it87 2>/dev/null | awk -F'[, ]+' '{print $2}' || true)
    for ver in $existing_versions; do
        if [ -n "$ver" ]; then
            log "Removing previous it87 DKMS version: $ver"
            dkms remove -m it87 -v "$ver" --all 2>/dev/null || true
            rm -rf "/usr/src/it87-${ver}" 2>/dev/null || true
        fi
    done

    # Build and install
    make clean 2>/dev/null || true
    make dkms

    # Verify module is loaded
    if lsmod | grep -q it87; then
        log "it87 driver loaded successfully"
    else
        local current_kernel
        current_kernel=$(uname -r)
        log "Loading it87 driver..."
        if is_hwmon_vid_builtin "$current_kernel"; then
            log "${HWMON_VID_MODULE} is built-in; skipping modprobe"
        else
            modprobe "$HWMON_VID_MODULE" 2>/dev/null || \
                modprobe "$HWMON_VID_MODULE_ALIAS" || \
                error "Failed to load required dependency ${HWMON_VID_MODULE} (alias ${HWMON_VID_MODULE_ALIAS})."
        fi
        modprobe it87 ignore_resource_conflict=1 || \
            error "Failed to load it87 driver. Check 'dmesg' for details."
    fi
}

install_modprobe_config() {
    log "Installing modprobe configuration..."
    cp "$REPO_DIR/config/it87-modprobe.conf" /etc/modprobe.d/it87.conf
    cp "$REPO_DIR/config/it87.conf" /etc/modules-load.d/it87.conf
    log "Module will be loaded automatically on boot"
}

install_services() {
    log "Installing systemd services..."

    # Install the config guard script
    install -m 755 "$REPO_DIR/scripts/fancontrol-config-guard.sh" /usr/local/sbin/fancontrol-config-guard.sh

    # Install systemd service files
    cp "$REPO_DIR/config/it87-driver.service" /etc/systemd/system/
    cp "$REPO_DIR/config/fancontrol-config-guard.service" /etc/systemd/system/

    # Create fancontrol drop-in to ensure proper service ordering.
    # Uses a uniquely named file to avoid overwriting admin drop-ins.
    mkdir -p /etc/systemd/system/fancontrol.service.d
    cat > /etc/systemd/system/fancontrol.service.d/ugreen-ordering.conf << 'EOF'
[Unit]
After=it87-driver.service fancontrol-config-guard.service
Requires=it87-driver.service
Wants=fancontrol-config-guard.service
EOF

    # Reload systemd and enable services
    systemctl daemon-reload
    systemctl enable it87-driver.service
    systemctl enable fancontrol-config-guard.service

    log "Systemd services installed and enabled"
}

create_initial_backup() {
    if [ -f /etc/fancontrol ]; then
        log "Creating initial backup of fancontrol configuration..."
        /usr/local/sbin/fancontrol-config-guard.sh backup || true
    else
        log "No existing fancontrol configuration found"
        log "Run 'sudo pwmconfig' to create one after installation"
    fi
}

print_status() {
    echo ""
    log "============================================="
    log "  Installation complete!"
    log "============================================="
    echo ""

    if lsmod | grep -q it87; then
        log "Driver status: LOADED"
    else
        log "Driver status: NOT LOADED (check 'dmesg' for errors)"
    fi

    if [ -f /etc/fancontrol ]; then
        log "Fan config:    FOUND (/etc/fancontrol)"
    else
        log "Fan config:    NOT FOUND - run 'sudo pwmconfig' to create"
    fi

    echo ""
    log "Next steps:"
    if [ ! -f /etc/fancontrol ]; then
        log "  1. Run 'sudo sensors-detect' to detect sensors"
        log "  2. Run 'sudo pwmconfig' to configure fan control"
        log "  3. Run 'sudo systemctl enable --now fancontrol' to start"
    else
        log "  1. Run 'sudo systemctl restart fancontrol' to apply changes"
    fi
    echo ""
}

# Main
check_root
check_dependencies
check_hwmon_vid
check_submodule
install_dkms
install_modprobe_config
install_services
create_initial_backup
print_status
