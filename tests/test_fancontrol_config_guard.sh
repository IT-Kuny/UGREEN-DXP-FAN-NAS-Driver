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
# iDX6011 Pro fan-control behavior
# ---------------------------------------------------------------------------
log_test "iDX6011 sensor-independent modes and target calculation"
FAN_MODE=max
read_cpu_temp() { return 1; }
read_disk_temps() { return 1; }
assert_eq "100 100" "$(idx6011_compute_targets)" "max mode works without temperature sensors"

FAN_MODE=auto
assert_eq "auto auto" "$(idx6011_compute_targets)" "auto mode works without temperature sensors"

FAN_MODE=invalid
UNKNOWN_MODE_STDERR=$(mktemp)
unknown_targets=$(idx6011_compute_targets 2>"$UNKNOWN_MODE_STDERR")
assert_eq "auto auto" "$unknown_targets" "unknown mode keeps stdout machine-readable"
if grep -q "Unknown iDX6011 FAN_MODE" "$UNKNOWN_MODE_STDERR"; then
    pass "unknown mode warning is written to stderr"
else
    fail "unknown mode warning is written to stderr"
fi
rm -f "$UNKNOWN_MODE_STDERR"

FAN_MODE=quiet
IDX6011_CPU_QUIET_CURVE="0:30,100:90"
IDX6011_DISK_QUIET_CURVE="0:30,100:100"
read_cpu_temp() { echo 50000; }
read_disk_temps() { echo 50000; }
assert_eq "60 65" "$(idx6011_compute_targets)" "quiet targets interpolate CPU and disk temperatures"
read_cpu_temp() { echo ""; }
read_disk_temps() { echo ""; }
if idx6011_compute_targets >/dev/null; then
    fail "quiet mode fails when all temperature sensors are unavailable"
else
    pass "quiet mode fails when all temperature sensors are unavailable"
fi

TEST_TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_TMP_DIR"' EXIT

log_test "PWM auto-detection keeps logs off stdout"
AUTO_HWMON_DIR="$TEST_TMP_DIR/sys/hwmon"
mkdir -p "$AUTO_HWMON_DIR/hwmon0"
echo "it8613" > "$AUTO_HWMON_DIR/hwmon0/name"
: > "$AUTO_HWMON_DIR/hwmon0/pwm3"
DETECT_LOG="$TEST_TMP_DIR/detect.log"
detected_path=$(auto_detect_pwm_path "$AUTO_HWMON_DIR" 2>"$DETECT_LOG")
assert_eq "$AUTO_HWMON_DIR/hwmon0/pwm3" "$detected_path" \
    "auto_detect_pwm_path returns only the PWM path"
if grep -Fq "Auto-detected UGREEN PWM path: $detected_path (driver: it8613)" "$DETECT_LOG"; then
    pass "auto_detect_pwm_path writes its log to stderr"
else
    fail "auto_detect_pwm_path writes its log to stderr"
fi

log_test "FAN_DEBUG keeps computed PWM stdout machine-readable"
DEBUG_LOG="$TEST_TMP_DIR/debug.log"
debug_target=$(FAN_DEBUG=1 compute_target_pwm 2>"$DEBUG_LOG")
assert_eq "110" "$debug_target" "compute_target_pwm returns only the target with debug enabled"
if grep -Fq "[DEBUG] CPU temp: 50°C -> PWM 100" "$DEBUG_LOG" &&
   grep -Fq "[DEBUG] Max disk temp: 45°C -> PWM 110" "$DEBUG_LOG"; then
    pass "compute_target_pwm writes debug logs to stderr"
else
    fail "compute_target_pwm writes debug logs to stderr"
fi

make_idx6011_hwmon() {
    local hwmon i
    hwmon=$(mktemp -d "$TEST_TMP_DIR/hwmon.XXXXXX")
    for i in 1 2 3 4; do
        : > "$hwmon/pwm${i}"
        echo 2 > "$hwmon/pwm${i}_enable"
        echo 1200 > "$hwmon/fan${i}_input"
    done
    echo "$hwmon"
}

log_test "iDX6011 paired writes apply both PWM channels"
PAIR_HWMON=$(make_idx6011_hwmon)
IDX6011_PWM_PATHS=("$PAIR_HWMON/pwm1" "$PAIR_HWMON/pwm2" "$PAIR_HWMON/pwm3" "$PAIR_HWMON/pwm4")
if idx6011_set_pair 0 128; then
    pass "CPU pair write succeeds"
else
    fail "CPU pair write succeeds"
fi
for i in 1 2; do
    assert_eq "128" "$(cat "$PAIR_HWMON/pwm${i}")" "CPU fan $i receives the paired duty"
    assert_eq "1" "$(cat "$PAIR_HWMON/pwm${i}_enable")" "CPU fan $i is enabled in manual mode"
done

run_idx6011_loop() {
    local hwmon="$1" scenario="$2" calls_file="$3" output_file="$4"
    (
        local ticks=0 test_cpu_raw=50000 test_disk_raw=50000
        set +e
        FAN_MODE=quiet
        read_cpu_temp() { printf '%s\n' "$test_cpu_raw"; }
        read_disk_temps() { printf '%s\n' "$test_disk_raw"; }
        idx6011_set_pair() {
            printf '%s %s\n' "$1" "$2" >> "$calls_file"
            if [[ "$scenario" == retry && "$1" == 0 ]] &&
               [[ $(grep -c '^0 ' "$calls_file") -eq 1 ]]; then
                return 1
            fi
            return 0
        }
        sleep() {
            ticks=$((ticks + 1))
            case "$scenario:$ticks" in
                recovery:1) test_cpu_raw=""; test_disk_raw="" ;;
                recovery:2) test_cpu_raw=50000; test_disk_raw=50000 ;;
                recovery:3) echo 0 > "$hwmon/fan1_input" ;;
                recovery:4) FAN_MODE=auto; test_cpu_raw=""; test_disk_raw="" ;;
                recovery:5|retry:2) exit 0 ;;
            esac
        }
        idx6011_main "$hwmon" > "$output_file" 2>&1
    )
}

log_test "iDX6011 sensor recovery, stall response, and EC handoff"
RECOVERY_HWMON=$(make_idx6011_hwmon)
RECOVERY_CALLS="$TEST_TMP_DIR/recovery.calls"
run_idx6011_loop "$RECOVERY_HWMON" recovery "$RECOVERY_CALLS" "$TEST_TMP_DIR/recovery.log"
assert_eq $'0 153\n2 165\n0 153\n2 165\n0 255\n2 255' \
    "$(cat "$RECOVERY_CALLS")" "sensor recovery reapplies targets and a stall forces both pairs to full speed"
for i in 1 2 3 4; do
    assert_eq "2" "$(cat "$RECOVERY_HWMON/pwm${i}_enable")" "auto mode returns fan $i to EC control"
done

log_test "iDX6011 failed pair writes are retried"
RETRY_HWMON=$(make_idx6011_hwmon)
RETRY_CALLS="$TEST_TMP_DIR/retry.calls"
run_idx6011_loop "$RETRY_HWMON" retry "$RETRY_CALLS" "$TEST_TMP_DIR/retry.log"
assert_eq $'0 153\n2 165\n0 153' "$(cat "$RETRY_CALLS")" \
    "failed CPU pair write is retried without rewriting the successful system pair"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
echo "=============================="

[ "$FAIL" -eq 0 ] || exit 1
