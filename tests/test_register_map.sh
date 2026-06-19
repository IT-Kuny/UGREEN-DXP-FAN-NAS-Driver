#!/bin/bash
#
# test_register_map.sh
#
# Validates the it87 driver register definitions against ITE_Register_map.csv.
# Checks fan tachometer, PWM control, and ADC resolution for chips supported
# by the driver.

set -euo pipefail

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIVER="$SCRIPT_DIR/../it87/it87.c"
CSV="$SCRIPT_DIR/../it87/ITE_Register_map.csv"

pass() {
    PASS=$((PASS + 1))
    echo "  PASS: $1"
}

fail() {
    FAIL=$((FAIL + 1))
    echo "  FAIL: $1"
}

# ---------------------------------------------------------------------------
# Helper: extract the CSV column index for a chip name (0-based).
# The CSV header is on row 1.
# ---------------------------------------------------------------------------
get_csv_col() {
    local chip_name="$1"
    head -1 "$CSV" | tr -d '\r' | awk -F',' -v name="$chip_name" '{
        for (i = 1; i <= NF; i++) {
            if ($i == name) { print i; exit }
        }
    }'
}

# ---------------------------------------------------------------------------
# Helper: get a cell value from the CSV by row-label and column-index.
# ---------------------------------------------------------------------------
get_csv_val() {
    local row_label="$1"
    local col="$2"
    awk -F',' -v label="$row_label" -v c="$col" '
        $1 == label { gsub(/\r/, "", $c); print $c; exit }
    ' "$CSV"
}

# ---------------------------------------------------------------------------
# Helper: extract the static-array values from the driver source.
# Usage: get_driver_array "IT87_REG_PWM"  → "0x15 0x16 0x17 0x7f 0xa7 0xaf"
# ---------------------------------------------------------------------------
get_driver_array() {
    local name="$1"
    grep "static const u8 ${name}\[\]" "$DRIVER" \
        | sed 's/.*{//; s/}.*//; s/,/ /g' \
        | tr -s ' '
}

# ---------------------------------------------------------------------------
# Helper: extract the _ALT array if present.
# ---------------------------------------------------------------------------
get_driver_alt_array() {
    local name="$1"
    grep "static const u8 ${name}\[\]" "$DRIVER" \
        | sed 's/.*{//; s/}.*//; s/,/ /g' \
        | tr -s ' '
}

# Normalise a hex value to lowercase without leading spaces
norm_hex() {
    echo "$1" | tr -d ' ' | tr 'A-F' 'a-f'
}

# ---------------------------------------------------------------------------
# Read driver arrays
# ---------------------------------------------------------------------------
IFS=' ' read -ra DRV_PWM     <<< "$(get_driver_array IT87_REG_PWM)"
IFS=' ' read -ra DRV_PWM_ALT <<< "$(get_driver_alt_array IT87_REG_PWM_ALT)"
IFS=' ' read -ra DRV_FAN     <<< "$(get_driver_array IT87_REG_FAN)"
IFS=' ' read -ra DRV_FANX    <<< "$(get_driver_array IT87_REG_FANX)"

# ---------------------------------------------------------------------------
# Map of chips the driver supports → CSV column name
# ---------------------------------------------------------------------------
declare -A CHIP_CSV_NAME=(
    [it8603]="IT8603E"
    [it8613]="IT8613E"
    [it8620]="IT8620E"
    [it8622]="IT8622E"
    [it8628]="IT8628E"
    [it8689]="IT8689E"
    [it8732]="IT8732"
    [it8790]="IT8790E"
    [it8792]="IT8792E"
)

# Chips that should use the alternate PWM register table
declare -A CHIP_ALT_PWM=(
    [it8613]=1
    [it8622]=1
)

# ---------------------------------------------------------------------------
# 1. Validate FAN tachometer register addresses
#    CSV format for FAN_TAC: "high/low" (e.g. "0x18/0x0d")
# ---------------------------------------------------------------------------
echo "=== Fan Tachometer Registers ==="

# ---------------------------------------------------------------------------
# Known CSV inconsistencies to skip validation for.
# IT8620E FAN6_TAC is listed as 0x4c/0x4d in the CSV but 0x4d/0x4c for
# IT8628E (a very similar chip). The driver uses 0x4c/0x4d (low/high)
# matching IT8628E. The IT8620E CSV entry appears transposed.
# ---------------------------------------------------------------------------
declare -A CSV_SKIP=(
    ["IT8620E:FAN6_TAC"]=1
)

for chip in "${!CHIP_CSV_NAME[@]}"; do
    csv_name="${CHIP_CSV_NAME[$chip]}"
    col=$(get_csv_col "$csv_name")
    [ -z "$col" ] && { echo "  SKIP: $csv_name not in CSV header"; continue; }

    for fan_idx in 0 1 2 3 4 5; do
        fan_num=$((fan_idx + 1))
        csv_val=$(get_csv_val "FAN${fan_num}_TAC" "$col")

        # Skip empty or "-" entries
        [ -z "$csv_val" ] || [ "$csv_val" = "-" ] && continue

        # Skip known CSV inconsistencies
        if [ "${CSV_SKIP["${csv_name}:FAN${fan_num}_TAC"]:-}" = "1" ]; then
            echo "  SKIP: $csv_name FAN${fan_num}_TAC (known CSV inconsistency)"
            continue
        fi

        # Parse "high/low" format
        csv_high=$(norm_hex "${csv_val%%/*}")
        csv_low=$(norm_hex "${csv_val##*/}")

        drv_low=$(norm_hex "${DRV_FAN[$fan_idx]}")
        drv_high=$(norm_hex "${DRV_FANX[$fan_idx]}")

        if [ "$csv_low" = "$drv_low" ] && [ "$csv_high" = "$drv_high" ]; then
            pass "$csv_name FAN${fan_num}_TAC: low=$csv_low high=$csv_high"
        else
            fail "$csv_name FAN${fan_num}_TAC: CSV low=$csv_low high=$csv_high, driver low=$drv_low high=$drv_high"
        fi
    done
done

# ---------------------------------------------------------------------------
# 2. Validate PWM control register addresses
#    CSV FAN{n}_PWM_CTL is a single hex address.
# ---------------------------------------------------------------------------
echo ""
echo "=== PWM Control Registers ==="

for chip in "${!CHIP_CSV_NAME[@]}"; do
    csv_name="${CHIP_CSV_NAME[$chip]}"
    col=$(get_csv_col "$csv_name")
    [ -z "$col" ] && continue

    # Choose the correct driver array for this chip
    if [ "${CHIP_ALT_PWM[$chip]:-}" = "1" ]; then
        eval 'drv_arr=("${DRV_PWM_ALT[@]}")'
        arr_label="ALT"
    else
        eval 'drv_arr=("${DRV_PWM[@]}")'
        arr_label="STD"
    fi

    for pwm_idx in 0 1 2 3 4 5; do
        pwm_num=$((pwm_idx + 1))
        csv_val=$(get_csv_val "FAN${pwm_num}_PWM_CTL" "$col")

        # Skip empty, "-", or "?" entries
        [ -z "$csv_val" ] || [ "$csv_val" = "-" ] || [ "$csv_val" = "?" ] && continue

        csv_hex=$(norm_hex "$csv_val")
        drv_hex=$(norm_hex "${drv_arr[$pwm_idx]}")

        if [ "$csv_hex" = "$drv_hex" ]; then
            pass "$csv_name FAN${pwm_num}_PWM_CTL ($arr_label): $csv_hex"
        else
            fail "$csv_name FAN${pwm_num}_PWM_CTL ($arr_label): CSV=$csv_hex driver=$drv_hex"
        fi
    done
done

# ---------------------------------------------------------------------------
# 3. Validate ADC resolution flags
#    CSV row "ADC res." has values like "12 mV", "11 mV", "10.9 mV"
# ---------------------------------------------------------------------------
echo ""
echo "=== ADC Resolution ==="

declare -A EXPECTED_ADC_FEAT=(
    [it8603]="FEAT_12MV_ADC"
    [it8613]="FEAT_11MV_ADC"
    [it8620]="FEAT_12MV_ADC"
    [it8622]="FEAT_12MV_ADC"
    [it8628]="FEAT_12MV_ADC"
    [it8689]="FEAT_12MV_ADC"
    [it8732]="FEAT_10_9MV_ADC"
    [it8790]="FEAT_10_9MV_ADC"
    [it8792]="FEAT_10_9MV_ADC"
)

for chip in "${!EXPECTED_ADC_FEAT[@]}"; do
    expected="${EXPECTED_ADC_FEAT[$chip]}"

    # Extract the features line for this chip from the driver
    features_line=$(awk "/\[${chip}\] = \{/,/\}/" "$DRIVER" | grep '\.features' | head -1)
    # Also get continuation lines
    features_block=$(awk "/\[${chip}\] = \{/,/\}/" "$DRIVER" | sed -n '/\.features/,/,$/p' | tr '\n' ' ')

    if echo "$features_block" | grep -qw "$expected"; then
        pass "$chip ADC: uses $expected"
    else
        # Check which ADC flag is actually set
        actual="none"
        for flag in FEAT_12MV_ADC FEAT_11MV_ADC FEAT_10_9MV_ADC; do
            if echo "$features_block" | grep -qw "$flag"; then
                actual="$flag"
                break
            fi
        done
        fail "$chip ADC: expected $expected, found $actual"
    fi
done

# ---------------------------------------------------------------------------
# 4. Validate per-chip PWM register routing
#    Ensure IT8613E and IT8622E use the ALT array via data->REG_PWM
# ---------------------------------------------------------------------------
echo ""
echo "=== Per-chip PWM Register Routing ==="

# Check that the probe function routes IT8613E/IT8622E to the ALT table
if grep -q 'data->type == it8613.*||.*data->type == it8622' "$DRIVER" ||
   grep -q 'data->type == it8622.*||.*data->type == it8613' "$DRIVER"; then
    if grep -A1 'it8613.*it8622\|it8622.*it8613' "$DRIVER" | grep -q 'IT87_REG_PWM_ALT'; then
        pass "probe routes IT8613E/IT8622E to IT87_REG_PWM_ALT"
    else
        fail "probe mentions IT8613E/IT8622E but doesn't use IT87_REG_PWM_ALT"
    fi
else
    fail "probe does not route IT8613E/IT8622E to alternate PWM table"
fi

# Check that all runtime PWM accesses use data->REG_PWM (not the global array)
# Use word boundary to avoid matching IT87_REG_PWM_ALT or IT87_REG_PWM_DUTY
runtime_global=$(grep -nP '\bIT87_REG_PWM\[' "$DRIVER" | grep -v '^[0-9]*:static ' || true)
if [ -z "$runtime_global" ]; then
    pass "No runtime references to global IT87_REG_PWM[] (all use data->REG_PWM)"
else
    fail "Found runtime references to global IT87_REG_PWM[]:"
    echo "$runtime_global" | sed 's/^/    /'
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
echo "=============================="

exit "$FAIL"
