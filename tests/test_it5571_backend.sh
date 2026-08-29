#!/bin/bash
#
# test_it5571_backend.sh
#
# Verifies the DXP6011 Pro / ITE5571 EC-backed support path in it87.c.

set -euo pipefail

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIVER="$SCRIPT_DIR/../it87/it87.c"

pass() {
    PASS=$((PASS + 1))
    echo "  PASS: $1"
}

fail() {
    FAIL=$((FAIL + 1))
    echo "  FAIL: $1"
}

check_contains() {
    local pattern="$1"
    local message="$2"

    if grep -qE "$pattern" "$DRIVER"; then
        pass "$message"
    else
        fail "$message"
    fi
}

echo "=== ITE5571 DXP6011 Pro backend ==="

check_contains '#define IT5571E_DEVID 0x5571' \
    'ITE5571 DEVID is defined'
check_contains 'DMI_PRODUCT_NAME, "iDX6011 Pro"' \
    'DXP6011 Pro DMI product string is matched'
check_contains '#define IT55_EC_DATA_PORT[[:space:]]+0x62' \
    'EC data port is defined'
check_contains '#define IT55_EC_CMD_PORT[[:space:]]+0x66' \
    'EC command port is defined'
check_contains 'request_muxed_region\(IT55_EC_DATA_PORT, 1, DRVNAME\)' \
    'EC data port is claimed individually'
check_contains 'request_muxed_region\(IT55_EC_CMD_PORT, 1, DRVNAME\)' \
    'EC command port is claimed individually'
check_contains 'static const u8 IT5571_REG_FAN_MODE\[\].*0xb0, 0xb2, 0xb4, 0xb6' \
    'manual/auto mode registers are defined'
check_contains 'static const u8 IT5571_REG_PWM_DUTY\[\].*0xb1, 0xb3, 0xb5, 0xb7' \
    'PWM duty registers are defined'
check_contains 'static const u8 IT5571_REG_FAN_MSB\[\].*0x34, 0x36, 0x38, 0x3a' \
    'fan tachometer MSB registers are defined'
check_contains 'static const u8 IT5571_REG_FAN_LSB\[\].*0x35, 0x37, 0x39, 0x3b' \
    'fan tachometer LSB registers are defined'
check_contains 'case IT5571E_DEVID:' \
    'probe recognizes the ITE5571 device ID'
check_contains 'if \(data->type == it5571\)' \
    'driver has a dedicated ITE5571 backend path'
check_contains 'it5571_group_fan' \
    'driver exposes a dedicated fan attribute group'
check_contains 'it5571_group_pwm' \
    'driver exposes a dedicated pwm attribute group'
check_contains 'return -EOPNOTSUPP;' \
    'unsupported EC fan modes return EOPNOTSUPP'

echo ""
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
echo "=============================="

exit "$FAIL"
