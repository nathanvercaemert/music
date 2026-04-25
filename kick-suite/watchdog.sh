#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/.runlogs"
LOGGING_LIB="${SCRIPT_DIR}/lib/logging.sh"
SONOBUS_RUN_SCRIPT="${SCRIPT_DIR}/sonobus-run.sh"
WATCHDOG_INTERVAL="${WATCHDOG_INTERVAL:-30}"
WATCHDOG_HEALTH_INTERVAL="${WATCHDOG_HEALTH_INTERVAL:-300}"
WATCHDOG_MIN_RESTART_INTERVAL="${WATCHDOG_MIN_RESTART_INTERVAL:-60}"
WATCHDOG_SUITE_GONE_THRESHOLD="${WATCHDOG_SUITE_GONE_THRESHOLD:-3}"

# shellcheck disable=SC1090
source "${LOGGING_LIB}"
ks_use_current_or_new
LOG_DIR="$(ks_log_subdir logs)"

mkdir -p "${LOG_DIR}"
ln -sfn "${LOG_DIR}/watchdog.log" "${SCRIPT_DIR}/.runlogs/watchdog.log" 2>/dev/null || true

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*"
}

sonobus_port_exists() {
  pw-link -i 2>/dev/null | grep -Fxq "SonoBus:in_1"
}

suite_is_running() {
  pw-link -o 2>/dev/null | grep -Fxq "output:out_0"
}

sonobus_log_error_hash() {
  local log_file="${LOG_DIR}/sonobus.log"
  local matches
  [[ -f "${log_file}" ]] || return 1
  matches="$(grep -Ei "channel count 0 out of range|aoo_source: sink not found|error|failed" "${log_file}" 2>/dev/null || true)"
  [[ -n "${matches}" ]] || return 1
  printf '%s\n' "${matches}" \
    | sha256sum \
    | awk '{ print $1 }'
}

restart_sonobus() {
  log "SonoBus is down; restarting via sonobus-run.sh"
  ks_event warn watchdog sonobus_restart_requested "SonoBus is down; restarting helper"
  if "${SONOBUS_RUN_SCRIPT}" 9<&-; then
    log "SonoBus restarted successfully."
    ks_event info watchdog sonobus_restart_success "SonoBus helper restarted successfully"
  else
    log "SonoBus restart failed (exit $?); will retry next cycle."
    ks_event error watchdog sonobus_restart_failed "SonoBus helper restart failed"
    ks_snapshot sonobus_restart_failed "sonobus-run.sh returned failure"
  fi
}

log "Watchdog started (interval=${WATCHDOG_INTERVAL}s, min_restart=${WATCHDOG_MIN_RESTART_INTERVAL}s)."
ks_event info watchdog watchdog_start "watchdog started" interval="${WATCHDOG_INTERVAL}" health_interval="${WATCHDOG_HEALTH_INTERVAL}" min_restart="${WATCHDOG_MIN_RESTART_INTERVAL}"
ks_log_health
ks_update_summary

last_restart=0
last_health="$(date +%s)"
last_sonobus_error_hash=""
suite_gone_count=0

while true; do
  sleep "${WATCHDOG_INTERVAL}"
  now="$(date +%s)"

  if (( now - last_health >= WATCHDOG_HEALTH_INTERVAL )); then
    ks_log_health
    ks_update_summary
    last_health="${now}"
  fi

  current_sonobus_error_hash="$(sonobus_log_error_hash || true)"
  if [[ -n "${current_sonobus_error_hash}" && "${current_sonobus_error_hash}" != "${last_sonobus_error_hash}" ]]; then
    last_sonobus_error_hash="${current_sonobus_error_hash}"
    log "SonoBus log contains a new relevant error signature."
    ks_event warn watchdog sonobus_log_error "SonoBus log contains relevant error signature" hash="${current_sonobus_error_hash}"
    ks_snapshot sonobus_log_error "SonoBus log error signature ${current_sonobus_error_hash}"
  fi

  if ! suite_is_running; then
    suite_gone_count=$(( suite_gone_count + 1 ))
    ks_event warn watchdog core_missing "core DSP modules not visible" missing="output:out_0" consecutive="${suite_gone_count}"
    if (( suite_gone_count == 1 )); then
      ks_snapshot core_missing "output:out_0 missing"
    fi
    if (( suite_gone_count >= WATCHDOG_SUITE_GONE_THRESHOLD )); then
      log "Core DSP modules missing for ${suite_gone_count} consecutive checks; watchdog exiting."
      ks_event error watchdog watchdog_exit_core_missing "core DSP modules missing for threshold; watchdog exiting" consecutive="${suite_gone_count}"
      ks_snapshot watchdog_exit_core_missing "core missing threshold reached"
      ks_update_summary
      exit 0
    fi
    log "Core DSP modules not visible (output:out_0 missing); check ${suite_gone_count}/${WATCHDOG_SUITE_GONE_THRESHOLD}."
    continue
  fi
  if (( suite_gone_count > 0 )); then
    ks_event info watchdog core_recovered "core DSP modules visible again" previous_missing_count="${suite_gone_count}"
  fi
  suite_gone_count=0

  if ! sonobus_port_exists; then
    elapsed=$(( now - last_restart ))
    ks_event warn watchdog sonobus_down "SonoBus input port is missing" elapsed_since_restart="${elapsed}"
    if (( elapsed < WATCHDOG_MIN_RESTART_INTERVAL )); then
      log "SonoBus is down but last restart was ${elapsed}s ago (min ${WATCHDOG_MIN_RESTART_INTERVAL}s); waiting."
      ks_event warn watchdog sonobus_restart_deferred "SonoBus restart deferred by minimum interval" elapsed_since_restart="${elapsed}"
    else
      last_restart="${now}"
      ks_snapshot sonobus_down "SonoBus:in_1 missing before restart"
      restart_sonobus
    fi
  fi
done
