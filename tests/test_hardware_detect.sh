#!/bin/bash
#
# test_hardware_detect.sh
#
# Tests for the hardware detection and AMD-specific configuration functions
# in scripts/install.sh.  These tests run without root by using temporary
# directories in place of the real system paths.

set -euo pipefail

PASS=0
FAIL=0
TEST_DIR=$(mktemp -d)

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

log_test() {
    echo "[TEST] $*"
}

pass() {
    PASS=$((PASS + 1))
    echo "  PASS: $1"
}

fail() {
    FAIL=$((FAIL + 1))
    echo "  FAIL: $1"
}

# ---------------------------------------------------------------------------
# Source install.sh in library mode (BASH_SOURCE guard prevents main from
# running; we override the root check and paths before sourcing).
# ---------------------------------------------------------------------------
SCRIPT_DIR_TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Override configurable paths so no real system files are touched
export CPU_INFO_PATH="$TEST_DIR/cpuinfo"
export GRUB_DEFAULT_FILE="$TEST_DIR/grub_default"
export SP5100_TCO_BLACKLIST="$TEST_DIR/sp5100_tco-blacklist.conf"

# Stub out root-requiring functions so sourcing does not abort
check_root()        { return 0; }
check_dependencies(){ return 0; }
check_hwmon_vid()   { return 0; }
check_submodule()   { return 0; }
install_dkms()      { return 0; }
install_modprobe_config() { return 0; }
install_amd_platform_config_real() { return 0; }
install_services()  { return 0; }
create_initial_backup() { return 0; }
print_status()      { return 0; }

# shellcheck source=/dev/null
. "$SCRIPT_DIR_TEST/scripts/install.sh"

# ---------------------------------------------------------------------------
# detect_cpu_vendor tests
# ---------------------------------------------------------------------------

log_test "detect_cpu_vendor — AMD (AuthenticAMD)"
printf 'vendor_id\t: AuthenticAMD\nmodel name\t: AMD Ryzen Embedded R2514\n' \
    > "$CPU_INFO_PATH"
result=$(detect_cpu_vendor)
if [ "$result" = "AMD" ]; then
    pass "Returns 'AMD' for AuthenticAMD"
else
    fail "Expected 'AMD', got '${result}'"
fi

log_test "detect_cpu_vendor — Intel (GenuineIntel)"
printf 'vendor_id\t: GenuineIntel\nmodel name\t: Intel(R) N100\n' \
    > "$CPU_INFO_PATH"
result=$(detect_cpu_vendor)
if [ "$result" = "Intel" ]; then
    pass "Returns 'Intel' for GenuineIntel"
else
    fail "Expected 'Intel', got '${result}'"
fi

log_test "detect_cpu_vendor — unknown / empty file"
: > "$CPU_INFO_PATH"
result=$(detect_cpu_vendor)
if [ "$result" = "Unknown" ]; then
    pass "Returns 'Unknown' for empty cpuinfo"
else
    fail "Expected 'Unknown', got '${result}'"
fi

log_test "detect_cpu_vendor — missing cpuinfo file"
CPU_INFO_PATH="$TEST_DIR/nonexistent_cpuinfo"
result=$(detect_cpu_vendor)
if [ "$result" = "Unknown" ]; then
    pass "Returns 'Unknown' when cpuinfo is missing"
else
    fail "Expected 'Unknown', got '${result}'"
fi
# Restore for subsequent tests
CPU_INFO_PATH="$TEST_DIR/cpuinfo"

# ---------------------------------------------------------------------------
# apply_grub_kernel_param tests
# ---------------------------------------------------------------------------

log_test "apply_grub_kernel_param — GRUB file absent"
rm -f "$GRUB_DEFAULT_FILE"
if ! apply_grub_kernel_param "acpi_enforce_resources=lax"; then
    pass "Returns non-zero when GRUB file is absent"
else
    fail "Should return non-zero when GRUB file is absent"
fi

log_test "apply_grub_kernel_param — appends to existing CMDLINE"
cat > "$GRUB_DEFAULT_FILE" << 'EOF'
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX=""
EOF
apply_grub_kernel_param "acpi_enforce_resources=lax"
if grep -q 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash acpi_enforce_resources=lax"' \
        "$GRUB_DEFAULT_FILE"; then
    pass "Parameter appended to existing GRUB_CMDLINE_LINUX_DEFAULT"
else
    fail "Parameter not found in expected position in GRUB file"
    echo "  File contents:"
    sed 's/^/    /' "$GRUB_DEFAULT_FILE"
fi

log_test "apply_grub_kernel_param — idempotent (already present)"
apply_grub_kernel_param "acpi_enforce_resources=lax"
count=$(grep -c "acpi_enforce_resources=lax" "$GRUB_DEFAULT_FILE")
if [ "$count" -eq 1 ]; then
    pass "Parameter added only once (idempotent)"
else
    fail "Parameter duplicated — found ${count} occurrences"
fi

log_test "apply_grub_kernel_param — empty CMDLINE"
cat > "$GRUB_DEFAULT_FILE" << 'EOF'
GRUB_CMDLINE_LINUX_DEFAULT=""
EOF
apply_grub_kernel_param "acpi_enforce_resources=lax"
if grep -q "acpi_enforce_resources=lax" "$GRUB_DEFAULT_FILE"; then
    pass "Parameter added to empty GRUB_CMDLINE_LINUX_DEFAULT"
else
    fail "Parameter not added to empty GRUB_CMDLINE_LINUX_DEFAULT"
fi

log_test "apply_grub_kernel_param — CMDLINE variable absent, creates it"
cat > "$GRUB_DEFAULT_FILE" << 'EOF'
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
EOF
apply_grub_kernel_param "acpi_enforce_resources=lax"
if grep -q "acpi_enforce_resources=lax" "$GRUB_DEFAULT_FILE"; then
    pass "Parameter added when GRUB_CMDLINE_LINUX_DEFAULT is absent"
else
    fail "Parameter not added when GRUB_CMDLINE_LINUX_DEFAULT is absent"
fi

# ---------------------------------------------------------------------------
# remove_grub_kernel_param tests
# ---------------------------------------------------------------------------

log_test "remove_grub_kernel_param — removes from middle of line"
cat > "$GRUB_DEFAULT_FILE" << 'EOF'
GRUB_CMDLINE_LINUX_DEFAULT="quiet acpi_enforce_resources=lax splash"
EOF
remove_grub_kernel_param "acpi_enforce_resources=lax"
if ! grep -q "acpi_enforce_resources=lax" "$GRUB_DEFAULT_FILE"; then
    pass "Parameter removed from middle of GRUB_CMDLINE_LINUX_DEFAULT"
else
    fail "Parameter still present after removal"
fi

log_test "remove_grub_kernel_param — removes from end of line"
cat > "$GRUB_DEFAULT_FILE" << 'EOF'
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash acpi_enforce_resources=lax"
EOF
remove_grub_kernel_param "acpi_enforce_resources=lax"
if ! grep -q "acpi_enforce_resources=lax" "$GRUB_DEFAULT_FILE"; then
    pass "Parameter removed from end of GRUB_CMDLINE_LINUX_DEFAULT"
else
    fail "Parameter still present after removal"
fi

log_test "remove_grub_kernel_param — no-op when absent"
cat > "$GRUB_DEFAULT_FILE" << 'EOF'
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
EOF
remove_grub_kernel_param "acpi_enforce_resources=lax"
if grep -q 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"' "$GRUB_DEFAULT_FILE"; then
    pass "File unchanged when parameter is absent"
else
    fail "File was modified even though parameter was not present"
fi

log_test "remove_grub_kernel_param — no-op when GRUB file absent"
rm -f "$GRUB_DEFAULT_FILE"
remove_grub_kernel_param "acpi_enforce_resources=lax"
pass "Returns without error when GRUB file is absent"

# ---------------------------------------------------------------------------
# install_amd_platform_config tests
# ---------------------------------------------------------------------------

log_test "install_amd_platform_config — writes sp5100_tco blacklist"
rm -f "$SP5100_TCO_BLACKLIST"
# Provide a GRUB file so apply_grub_kernel_param succeeds without GRUB tools
cat > "$GRUB_DEFAULT_FILE" << 'EOF'
GRUB_CMDLINE_LINUX_DEFAULT="quiet"
EOF
install_amd_platform_config
if [ -f "$SP5100_TCO_BLACKLIST" ]; then
    pass "sp5100_tco blacklist file created"
else
    fail "sp5100_tco blacklist file not created"
fi

log_test "install_amd_platform_config — blacklist contains correct directive"
if grep -q "blacklist sp5100_tco" "$SP5100_TCO_BLACKLIST"; then
    pass "Blacklist file contains 'blacklist sp5100_tco'"
else
    fail "Blacklist file missing 'blacklist sp5100_tco'"
fi

log_test "install_amd_platform_config — GRUB param added when GRUB present"
if grep -q "acpi_enforce_resources=lax" "$GRUB_DEFAULT_FILE"; then
    pass "acpi_enforce_resources=lax added to GRUB when file present"
else
    fail "acpi_enforce_resources=lax not found in GRUB file"
fi

log_test "install_amd_platform_config — idempotent (run twice)"
install_amd_platform_config
count=$(grep -c "acpi_enforce_resources=lax" "$GRUB_DEFAULT_FILE")
if [ "$count" -eq 1 ]; then
    pass "Running install_amd_platform_config twice does not duplicate GRUB param"
else
    fail "GRUB param duplicated — found ${count} occurrences"
fi
blacklist_lines=$(grep -c "blacklist sp5100_tco" "$SP5100_TCO_BLACKLIST")
if [ "$blacklist_lines" -eq 1 ]; then
    pass "Running install_amd_platform_config twice does not duplicate blacklist line"
else
    fail "Blacklist entry duplicated — found ${blacklist_lines} occurrences"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================="
echo "  Test Results: $PASS passed, $FAIL failed"
echo "============================================="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
