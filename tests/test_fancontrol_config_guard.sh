#!/bin/bash
#
# test_fancontrol_config_guard.sh
#
# Unit-style tests for fan curve parsing/interpolation/target PWM logic
# in scripts/ugreen-fan-control.sh.

set -euo pipefail

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAN_SCRIPT="$SCRIPT_DIR/scripts/ugreen-fan-control.sh"

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

assert_eq() {
    local expected="$1"
    local actual="$2"
    local name="$3"
    if [ "$actual" = "$expected" ]; then
        pass "$name"
    else
        fail "$name (expected '$expected', got '$actual')"
    fi
}

# Load functions without executing main.
# shellcheck source=/dev/null
source "$FAN_SCRIPT"

setup_curves() {
    parse_curve "35:50,50:100,65:180,75:255"
    CPU_CURVE_TEMPS=("${CURVE_TEMPS[@]}")
    CPU_CURVE_PWMS=("${CURVE_PWMS[@]}")

    parse_curve "35:60,45:110,55:180,60:255"
    DISK_CURVE_TEMPS=("${CURVE_TEMPS[@]}")
    DISK_CURVE_PWMS=("${CURVE_PWMS[@]}")
}

# ---------------------------------------------------------------------------
# parse_curve
# ---------------------------------------------------------------------------
log_test "parse_curve handles integer and decimal points"
parse_curve "35:50,50.5:100.25"
assert_eq "2" "${#CURVE_TEMPS[@]}" "parse_curve returns two temperature points"
assert_eq "2" "${#CURVE_PWMS[@]}" "parse_curve returns two PWM points"
assert_eq "35000" "${CURVE_TEMPS[0]}" "parse_curve scales first temperature"
assert_eq "50500" "${CURVE_TEMPS[1]}" "parse_curve scales decimal temperature"
assert_eq "50000" "${CURVE_PWMS[0]}" "parse_curve scales first PWM"
assert_eq "100250" "${CURVE_PWMS[1]}" "parse_curve scales decimal PWM"

# ---------------------------------------------------------------------------
# interpolate_curve
# ---------------------------------------------------------------------------
log_test "interpolate_curve clamps and interpolates correctly"
test_temps=(35000 50000 65000)
test_pwms=(50000 100000 180000)
assert_eq "50" "$(interpolate_curve 30000 test_temps test_pwms)" "interpolate_curve clamps below range"
assert_eq "180" "$(interpolate_curve 70000 test_temps test_pwms)" "interpolate_curve clamps above range"
assert_eq "140" "$(interpolate_curve 57500 test_temps test_pwms)" "interpolate_curve linearly interpolates midpoint"

# ---------------------------------------------------------------------------
# compute_target_pwm
# ---------------------------------------------------------------------------
log_test "compute_target_pwm chooses max source and clamps"
setup_curves
MIN_PWM=60
MAX_PWM=200

read_cpu_temp() { echo "50000"; }
read_disk_temps() { echo "45000"; }
log_debug() { :; }
assert_eq "110" "$(compute_target_pwm)" "compute_target_pwm chooses higher of CPU/DISK curves"

read_cpu_temp() { echo "80000"; }
read_disk_temps() { echo ""; }
assert_eq "200" "$(compute_target_pwm)" "compute_target_pwm clamps to MAX_PWM"

read_cpu_temp() { echo ""; }
read_disk_temps() { echo ""; }
if compute_target_pwm >/dev/null 2>&1; then
    fail "compute_target_pwm should fail when all sensors are unavailable"
else
    pass "compute_target_pwm fails when all sensors are unavailable"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
echo "=============================="

[ "$FAIL" -eq 0 ] || exit 1
