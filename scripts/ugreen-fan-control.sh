#!/bin/bash
#
# ugreen-fan-control.sh
#
# Automatic fan control daemon for UGREEN DXP NAS devices.
#
# Features:
#  - Dual independent fan curves: CPU temperature and storage (NVMe/SATA) temperature.
#  - Three selectable curve presets: silent, normal, powerful.
#  - Piecewise-linear PWM interpolation between curve points.
#  - Auto-detection of the ITE Super I/O hwmon PWM sysfs path.
#  - Explicit manual-mode activation (pwmN_enable=1) before every write.
#  - HDD standby protection: drives in standby/sleep are skipped to avoid
#    unnecessary spin-up during temperature polling.
#  - Failsafe: reverts to FAILSAFE_PWM on any sensor-read failure.
#
# Configuration is read from /etc/ugreen/ugreen-fan-control.env (EnvironmentFile).
# All variables have safe defaults so the daemon works out of the box.

set -uo pipefail

# ---------------------------------------------------------------------------
# Configuration defaults (overridden by EnvironmentFile in the service unit)
# ---------------------------------------------------------------------------
POLL_INTERVAL="${POLL_INTERVAL:-10}"
FAILSAFE_PWM="${FAILSAFE_PWM:-200}"
MIN_PWM="${MIN_PWM:-50}"
MAX_PWM="${MAX_PWM:-255}"
FAN_MODE="${FAN_MODE:-normal}"

CPU_FAN_CURVE="${CPU_FAN_CURVE:-35:50,50:100,65:180,75:255}"
DISK_FAN_CURVE="${DISK_FAN_CURVE:-35:60,45:110,55:180,60:255}"

SILENT_CPU_FAN_CURVE="${SILENT_CPU_FAN_CURVE:-40:0,55:40,65:80,75:150}"
SILENT_DISK_FAN_CURVE="${SILENT_DISK_FAN_CURVE:-38:0,45:40,55:80,62:150}"

POWERFUL_CPU_FAN_CURVE="${POWERFUL_CPU_FAN_CURVE:-30:120,45:180,55:220,65:255}"
POWERFUL_DISK_FAN_CURVE="${POWERFUL_DISK_FAN_CURVE:-30:120,40:180,50:220,55:255}"

# Optional override for the PWM sysfs path (leave empty for auto-detection).
FAN_PWM_PATH="${FAN_PWM_PATH:-}"

# Optional override for the CPU temperature sysfs input file.
CPU_TEMP_PATH="${CPU_TEMP_PATH:-}"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log_info()  { echo "$(date '+%Y-%m-%d %T') [INFO]  $*"; }
log_warn()  { echo "$(date '+%Y-%m-%d %T') [WARN]  $*"; }
log_error() { echo "$(date '+%Y-%m-%d %T') [ERROR] $*" >&2; }
log_debug() {
    if [[ "${FAN_DEBUG:-0}" == "1" ]]; then
        echo "$(date '+%Y-%m-%d %T') [DEBUG] $*"
    fi
}

# ---------------------------------------------------------------------------
# Integer arithmetic helpers (bash only; no floating-point builtins)
# ---------------------------------------------------------------------------

# Scale factor: temperatures and PWM values are multiplied by 1000 internally
# so that we can do fixed-point arithmetic with plain integer division.
readonly SCALE=1000

# multiply_scaled A B  ->  prints A*B/SCALE  (i.e. one SCALE factor cancels)
multiply_scaled() {
    echo $(( ($1 * $2) / SCALE ))
}

# clamp VALUE MIN MAX  ->  prints value clamped to [MIN,MAX]
clamp() {
    local val=$1 lo=$2 hi=$3
    if (( val < lo )); then echo "$lo"
    elif (( val > hi )); then echo "$hi"
    else echo "$val"
    fi
}

# ---------------------------------------------------------------------------
# Curve parsing
#
# parse_curve CURVE_STRING  ->  sets global arrays CURVE_TEMPS[] CURVE_PWMS[]
#
# Curve string format: "t1:p1,t2:p2,..."  (values are plain integers or decimals)
# Internally we store temps * SCALE (integer millidegrees) and pwm * SCALE.
# ---------------------------------------------------------------------------
parse_curve() {
    local curve_str="$1"
    CURVE_TEMPS=()
    CURVE_PWMS=()

    local pair
    IFS=',' read -ra pairs <<< "$curve_str"
    for pair in "${pairs[@]}"; do
        pair="${pair// /}"  # strip spaces
        if [[ "$pair" == *:* ]]; then
            local t="${pair%%:*}"
            local p="${pair##*:}"
            # Convert to integer millivalue (handles simple decimals like "35.5")
            CURVE_TEMPS+=( "$(awk -v value="$t" -v scale="$SCALE" 'BEGIN{printf "%d", value * scale}')" )
            CURVE_PWMS+=(  "$(awk -v value="$p" -v scale="$SCALE" 'BEGIN{printf "%d", value * scale}')" )
        fi
    done
}

# ---------------------------------------------------------------------------
# interpolate_curve TEMP_SCALED TEMPS_ARRAY PWMS_ARRAY -> prints pwm (integer)
#
# Piecewise-linear interpolation between the curve points.
# Clamps at the first/last point outside the curve range.
# ---------------------------------------------------------------------------
interpolate_curve() {
    local temp_s="$1"
    shift
    local -n _temps="$1"
    shift
    local -n _pwms="$1"

    local n="${#_temps[@]}"
    if (( n == 0 )); then
        echo 0
        return
    fi

    if (( temp_s <= _temps[0] )); then
        echo $(( _pwms[0] / SCALE ))
        return
    fi

    if (( temp_s >= _temps[n-1] )); then
        echo $(( _pwms[n-1] / SCALE ))
        return
    fi

    local i
    for (( i = 0; i < n - 1; i++ )); do
        local t1="${_temps[$i]}"
        local t2="${_temps[$((i+1))]}"
        local p1="${_pwms[$i]}"
        local p2="${_pwms[$((i+1))]}"

        if (( temp_s >= t1 && temp_s <= t2 )); then
            local range=$(( t2 - t1 ))
            local offset=$(( temp_s - t1 ))
            # pwm = p1 + (p2 - p1) * offset / range   (all scaled)
            local pwm_s=$(( p1 + (p2 - p1) * offset / range ))
            echo $(( pwm_s / SCALE ))
            return
        fi
    done

    echo $(( _pwms[n-1] / SCALE ))
}

# ---------------------------------------------------------------------------
# PWM path auto-detection
# ---------------------------------------------------------------------------
auto_detect_pwm_path() {
    local hwmon name pwm_path
    for hwmon in /sys/class/hwmon/hwmon*; do
        [[ -f "$hwmon/name" ]] || continue
        name=$(cat "$hwmon/name" 2>/dev/null) || continue
        if [[ "$name" == it8* || "$name" == it87* || "$name" == it86* ]]; then
            for pwm in pwm3 pwm2 pwm1; do
                pwm_path="$hwmon/$pwm"
                if [[ -f "$pwm_path" ]]; then
                    log_info "Auto-detected UGREEN PWM path: $pwm_path (driver: $name)"
                    echo "$pwm_path"
                    return 0
                fi
            done
        fi
    done
    return 1
}

# ---------------------------------------------------------------------------
# Manual PWM mode — write 1 to pwmN_enable if not already set
# ---------------------------------------------------------------------------
enable_manual_pwm() {
    local pwm_path="$1"
    local enable_path="${pwm_path}_enable"
    [[ -f "$enable_path" ]] || return 0

    local current
    current=$(cat "$enable_path" 2>/dev/null) || return 0
    if [[ "$current" == "1" ]]; then
        return 0
    fi

    if echo 1 > "$enable_path" 2>/dev/null; then
        log_info "Set $enable_path to manual mode (1)"
    else
        log_warn "Failed to set $enable_path to manual mode"
    fi
}

# ---------------------------------------------------------------------------
# Temperature reading
# ---------------------------------------------------------------------------

# read_cpu_temp -> prints temperature in millidegrees (integer), or "" on failure
read_cpu_temp() {
    # Optional direct path override
    if [[ -n "$CPU_TEMP_PATH" && -f "$CPU_TEMP_PATH" ]]; then
        local v
        v=$(cat "$CPU_TEMP_PATH" 2>/dev/null) && echo "$v" && return
    fi

    local max_temp=0 found=0 hwmon name temp_input v
    for hwmon in /sys/class/hwmon/hwmon*; do
        [[ -f "$hwmon/name" ]] || continue
        name=$(cat "$hwmon/name" 2>/dev/null) || continue
        case "$name" in
            coretemp|k10temp|acpitz|cpu_thermal)
                for temp_input in "$hwmon"/temp*_input; do
                    [[ -f "$temp_input" ]] || continue
                    v=$(cat "$temp_input" 2>/dev/null) || continue
                    # Sanity: 0 < temp < 120 000 millidegrees
                    if (( v > 0 && v < 120000 )); then
                        found=1
                        (( v > max_temp )) && max_temp="$v"
                    fi
                done
                ;;
        esac
    done

    if (( found )); then
        echo "$max_temp"
    fi
}

# read_disk_temps -> prints space-separated list of temperatures in millidegrees
read_disk_temps() {
    local temps=() hwmon name temp_input v

    # NVMe and drivetemp (kernel SATA temperature module)
    for hwmon in /sys/class/hwmon/hwmon*; do
        [[ -f "$hwmon/name" ]] || continue
        name=$(cat "$hwmon/name" 2>/dev/null) || continue
        case "$name" in
            nvme|drivetemp)
                for temp_input in "$hwmon"/temp*_input; do
                    [[ -f "$temp_input" ]] || continue
                    v=$(cat "$temp_input" 2>/dev/null) || continue
                    if (( v > 0 && v < 120000 )); then
                        temps+=("$v")
                    fi
                done
                ;;
        esac
    done

    # Fallback: smartctl for SATA drives not covered by drivetemp.
    # Only probe drives that are not in standby/sleep to avoid wake-ups.
    if (( ${#temps[@]} == 0 )) && command -v smartctl &>/dev/null; then
        local dev
        for dev in /dev/sd[a-z]; do
            [[ -b "$dev" ]] || continue

            # -n standby exits non-zero (exit code bit 1 set) when drive is asleep
            local state_json
            state_json=$(smartctl -n standby -j "$dev" 2>/dev/null) || {
                # bit 1 (value 2) in exit status means drive is in standby
                local ec=$?
                (( (ec & 2) != 0 )) && continue
                # Other errors: skip this drive
                continue
            }

            local temp
            temp=$(echo "$state_json" | \
                   awk -F'[",: ]+' '/"current"/{found=1; next} found{print int($1)*1000; exit}' \
                   2>/dev/null) || continue
            if [[ -n "$temp" ]] && (( temp > 0 && temp < 120000 )); then
                temps+=("$temp")
            fi
        done
    fi

    echo "${temps[*]:-}"
}

# max of space-separated integer list -> prints max or 0
list_max() {
    local max=0 v
    for v in $1; do
        (( v > max )) && max="$v"
    done
    echo "$max"
}

# ---------------------------------------------------------------------------
# Apply a PWM value to the fan controller
# ---------------------------------------------------------------------------
apply_pwm() {
    local pwm_path="$1" target="$2"
    enable_manual_pwm "$pwm_path"
    if echo "$target" > "$pwm_path" 2>/dev/null; then
        return 0
    else
        log_error "Failed to write PWM $target to $pwm_path"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    log_info "UGREEN Fan Control Daemon starting"

    # Select fan curves based on FAN_MODE
    local cpu_curve_str disk_curve_str
    case "${FAN_MODE,,}" in
        silent)
            cpu_curve_str="$SILENT_CPU_FAN_CURVE"
            disk_curve_str="$SILENT_DISK_FAN_CURVE"
            ;;
        powerful)
            cpu_curve_str="$POWERFUL_CPU_FAN_CURVE"
            disk_curve_str="$POWERFUL_DISK_FAN_CURVE"
            ;;
        normal|*)
            if [[ "${FAN_MODE,,}" != "normal" ]]; then
                log_warn "Unknown FAN_MODE '${FAN_MODE}', falling back to 'normal'"
            fi
            cpu_curve_str="$CPU_FAN_CURVE"
            disk_curve_str="$DISK_FAN_CURVE"
            ;;
    esac

    # Parse curves into global arrays
    declare -a CPU_CURVE_TEMPS CPU_CURVE_PWMS DISK_CURVE_TEMPS DISK_CURVE_PWMS
    parse_curve "$cpu_curve_str"
    CPU_CURVE_TEMPS=("${CURVE_TEMPS[@]}")
    CPU_CURVE_PWMS=("${CURVE_PWMS[@]}")

    parse_curve "$disk_curve_str"
    DISK_CURVE_TEMPS=("${CURVE_TEMPS[@]}")
    DISK_CURVE_PWMS=("${CURVE_PWMS[@]}")

    # Resolve PWM path
    local pwm_path="$FAN_PWM_PATH"
    if [[ -z "$pwm_path" ]]; then
        pwm_path=$(auto_detect_pwm_path) || {
            log_error "Could not detect UGREEN PWM sysfs path. Exiting."
            exit 1
        }
    fi
    if [[ ! -f "$pwm_path" ]]; then
        log_error "PWM path does not exist: $pwm_path. Exiting."
        exit 1
    fi

    log_info "Fan Mode       : ${FAN_MODE}"
    log_info "PWM Path       : ${pwm_path}"
    log_info "Poll Interval  : ${POLL_INTERVAL}s"
    log_info "PWM Range      : ${MIN_PWM}–${MAX_PWM}"
    log_info "CPU Curve      : ${cpu_curve_str}"
    log_info "Disk Curve     : ${disk_curve_str}"

    local current_pwm=""

    # Graceful shutdown: restore failsafe PWM on SIGTERM/SIGINT
    cleanup() {
        log_info "Received signal, applying failsafe PWM (${FAILSAFE_PWM}) and exiting"
        apply_pwm "$pwm_path" "$FAILSAFE_PWM" || true
        exit 0
    }
    trap cleanup SIGTERM SIGINT

    while true; do
        local target_pwm

        if ! target_pwm=$(compute_target_pwm); then
            log_warn "Sensor read failure — applying failsafe PWM (${FAILSAFE_PWM})"
            target_pwm="$FAILSAFE_PWM"
        fi

        if [[ "$target_pwm" != "$current_pwm" ]]; then
            if apply_pwm "$pwm_path" "$target_pwm"; then
                log_info "Applied PWM: ${target_pwm}"
                current_pwm="$target_pwm"
            else
                # If the write failed, try to write failsafe as a last resort
                apply_pwm "$pwm_path" "$FAILSAFE_PWM" || true
                current_pwm="$FAILSAFE_PWM"
            fi
        fi

        sleep "$POLL_INTERVAL"
    done
}

# compute_target_pwm -> prints final integer PWM value, returns 1 on sensor failure
compute_target_pwm() {
    local cpu_temp_raw disk_temps_raw
    cpu_temp_raw=$(read_cpu_temp)
    disk_temps_raw=$(read_disk_temps)

    if [[ -z "$cpu_temp_raw" && -z "$disk_temps_raw" ]]; then
        return 1
    fi

    local cpu_pwm=0 disk_pwm=0

    if [[ -n "$cpu_temp_raw" ]]; then
        cpu_pwm=$(interpolate_curve "$cpu_temp_raw" CPU_CURVE_TEMPS CPU_CURVE_PWMS)
        log_debug "CPU temp: $(( cpu_temp_raw / 1000 ))°C -> PWM $cpu_pwm"
    fi

    if [[ -n "$disk_temps_raw" ]]; then
        local max_disk_temp
        max_disk_temp=$(list_max "$disk_temps_raw")
        disk_pwm=$(interpolate_curve "$max_disk_temp" DISK_CURVE_TEMPS DISK_CURVE_PWMS)
        log_debug "Max disk temp: $(( max_disk_temp / 1000 ))°C -> PWM $disk_pwm"
    fi

    local target=$(( cpu_pwm > disk_pwm ? cpu_pwm : disk_pwm ))
    target=$(clamp "$target" "$MIN_PWM" "$MAX_PWM")
    echo "$target"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
