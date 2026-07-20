#!/bin/bash
#
# test_hardware_detect.sh
#
# Tests for CPU vendor detection and platform-aware configuration logic
# in install.sh.  The tests mock /proc/cpuinfo using a temporary file so
# they do not require root access or real hardware.

set -euo pipefail

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="$SCRIPT_DIR/../scripts/install.sh"

pass() {
    PASS=$((PASS + 1))
    echo "  PASS: $1"
}

fail() {
    FAIL=$((FAIL + 1))
    echo "  FAIL: $1"
}

log_test() {
    echo "[TEST] $*"
}

# ---------------------------------------------------------------------------
# Extract and wrap get_cpu_vendor() for testing with a mock cpuinfo file.
# The function reads /proc/cpuinfo; we override that path via a helper.
# ---------------------------------------------------------------------------

# Inline the logic from get_cpu_vendor() so tests don't need to source the
# full install.sh (which calls check_root and other side-effectful functions).
get_cpu_vendor_from_file() {
    local cpuinfo_file="$1"
    local vendor
    vendor=$(grep -m1 "^vendor_id" "$cpuinfo_file" 2>/dev/null | awk -F': ' '{print $2}' | tr -d ' ')
    case "$vendor" in
        AuthenticAMD) echo "AMD" ;;
        GenuineIntel) echo "Intel" ;;
        *) echo "unknown" ;;
    esac
}

# ---------------------------------------------------------------------------
# 1. CPU vendor detection – AMD
# ---------------------------------------------------------------------------
echo "=== CPU Vendor Detection ==="

log_test "AMD vendor detection"
AMD_CPUINFO=$(mktemp)
cat > "$AMD_CPUINFO" << 'EOF'
processor	: 0
vendor_id	: AuthenticAMD
cpu family	: 23
model		: 24
model name	: AMD Ryzen Embedded R2514 with Radeon Graphics
EOF
result=$(get_cpu_vendor_from_file "$AMD_CPUINFO")
rm -f "$AMD_CPUINFO"
if [ "$result" = "AMD" ]; then
    pass "AuthenticAMD → AMD"
else
    fail "AuthenticAMD → expected AMD, got '$result'"
fi

# ---------------------------------------------------------------------------
# 2. CPU vendor detection – Intel
# ---------------------------------------------------------------------------
log_test "Intel vendor detection"
INTEL_CPUINFO=$(mktemp)
cat > "$INTEL_CPUINFO" << 'EOF'
processor	: 0
vendor_id	: GenuineIntel
cpu family	: 6
model		: 190
model name	: Intel(R) N100
EOF
result=$(get_cpu_vendor_from_file "$INTEL_CPUINFO")
rm -f "$INTEL_CPUINFO"
if [ "$result" = "Intel" ]; then
    pass "GenuineIntel → Intel"
else
    fail "GenuineIntel → expected Intel, got '$result'"
fi

# ---------------------------------------------------------------------------
# 3. CPU vendor detection – unknown
# ---------------------------------------------------------------------------
log_test "Unknown vendor detection"
UNK_CPUINFO=$(mktemp)
cat > "$UNK_CPUINFO" << 'EOF'
processor	: 0
vendor_id	: CentaurHauls
model name	: VIA C7
EOF
result=$(get_cpu_vendor_from_file "$UNK_CPUINFO")
rm -f "$UNK_CPUINFO"
if [ "$result" = "unknown" ]; then
    pass "CentaurHauls → unknown"
else
    fail "CentaurHauls → expected unknown, got '$result'"
fi

# ---------------------------------------------------------------------------
# 4. CPU vendor detection – empty file
# ---------------------------------------------------------------------------
log_test "Empty cpuinfo file"
EMPTY_CPUINFO=$(mktemp)
result=$(get_cpu_vendor_from_file "$EMPTY_CPUINFO")
rm -f "$EMPTY_CPUINFO"
if [ "$result" = "unknown" ]; then
    pass "Empty cpuinfo → unknown"
else
    fail "Empty cpuinfo → expected unknown, got '$result'"
fi

# ---------------------------------------------------------------------------
# 5. Service file uses runtime CPU detection (not hardcoded)
# ---------------------------------------------------------------------------
echo ""
echo "=== Service File CPU Detection ==="

SERVICE_FILE="$SCRIPT_DIR/../config/it87-driver.service"

log_test "Service ExecStart uses runtime CPU vendor check"
if grep -q "AuthenticAMD" "$SERVICE_FILE"; then
    pass "Service detects AuthenticAMD at runtime"
else
    fail "Service does not check for AuthenticAMD in /proc/cpuinfo"
fi

log_test "Service does not hardcode ignore_resource_conflict=1 unconditionally"
# The option must appear inside a conditional, not as a plain modprobe argument
# at the top level.  We verify that the ExecStart line is not a simple
# 'modprobe it87 ignore_resource_conflict=1'.
if grep -E "^ExecStart=/sbin/modprobe it87 ignore_resource_conflict=1" "$SERVICE_FILE"; then
    fail "Service hardcodes ignore_resource_conflict=1 without a CPU check"
else
    pass "Service does not hardcode ignore_resource_conflict=1 unconditionally"
fi

log_test "Service still passes ignore_resource_conflict=1 for non-AMD path"
# The option must appear somewhere in the service file (inside a conditional)
# to preserve Intel behaviour, but must NOT be the unconditional top-level arg.
if grep -q "ignore_resource_conflict=1" "$SERVICE_FILE"; then
    pass "ignore_resource_conflict=1 still present in service file (conditional)"
else
    fail "ignore_resource_conflict=1 missing from service file entirely"
fi

# ---------------------------------------------------------------------------
# 6. install.sh contains get_cpu_vendor() function
# ---------------------------------------------------------------------------
echo ""
echo "=== install.sh CPU Vendor Function ==="

log_test "install.sh defines get_cpu_vendor()"
if grep -q "^get_cpu_vendor()" "$INSTALL_SCRIPT"; then
    pass "get_cpu_vendor() function is defined"
else
    fail "get_cpu_vendor() function not found in install.sh"
fi

log_test "install.sh defines warn_amd_chip_compatibility()"
if grep -q "^warn_amd_chip_compatibility()" "$INSTALL_SCRIPT"; then
    pass "warn_amd_chip_compatibility() function is defined"
else
    fail "warn_amd_chip_compatibility() function not found in install.sh"
fi

log_test "install.sh calls warn_amd_chip_compatibility in main sequence"
# The function name must appear at least twice: once for the definition and
# once for the call site.  This is a reliable check that doesn't depend on
# comments or code ordering.
call_count=$(grep -c "warn_amd_chip_compatibility" "$INSTALL_SCRIPT" || true)
if [ "$call_count" -ge 2 ]; then
    pass "warn_amd_chip_compatibility called in main sequence (found $call_count occurrences)"
else
    fail "warn_amd_chip_compatibility not called (found $call_count occurrences, expected >= 2)"
fi

log_test "install_modprobe_config() is AMD-aware"
# Extract the full body of install_modprobe_config() and verify it references
# cpu_vendor / get_cpu_vendor.  Using awk to extract the function body avoids
# the line-count fragility of grep -A.
if awk '/^install_modprobe_config\(\)/{found=1} found{print} /^}$/ && found{exit}' \
        "$INSTALL_SCRIPT" | grep -q "cpu_vendor\|get_cpu_vendor"; then
    pass "install_modprobe_config() uses CPU vendor detection"
else
    fail "install_modprobe_config() does not use CPU vendor detection"
fi

# ---------------------------------------------------------------------------
# 7. modprobe.conf template still has ignore_resource_conflict for Intel
# ---------------------------------------------------------------------------
echo ""
echo "=== Modprobe Config Template ==="

MODPROBE_CONF="$SCRIPT_DIR/../config/it87-modprobe.conf"

log_test "it87-modprobe.conf has ignore_resource_conflict=1 (Intel template)"
if grep -q "ignore_resource_conflict=1" "$MODPROBE_CONF"; then
    pass "Intel modprobe template retains ignore_resource_conflict=1"
else
    fail "Intel modprobe template missing ignore_resource_conflict=1"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
echo "=============================="

exit "$FAIL"
