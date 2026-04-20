#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/.runlogs"
SONOBUS_RUN_SCRIPT="${SCRIPT_DIR}/sonobus-run.sh"
WATCHDOG_INTERVAL="${WATCHDOG_INTERVAL:-30}"
WATCHDOG_MIN_RESTART_INTERVAL="${WATCHDOG_MIN_RESTART_INTERVAL:-60}"
WATCHDOG_SUITE_GONE_THRESHOLD="${WATCHDOG_SUITE_GONE_THRESHOLD:-3}"

mkdir -p "${LOG_DIR}"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*"
}

sonobus_port_exists() {
  pw-link -i 2>/dev/null | grep -Fxq "SonoBus:in_1"
}

suite_is_running() {
  pw-link -o 2>/dev/null | grep -Fxq "output:out_0"
}

restart_sonobus() {
  log "SonoBus is down; restarting via sonobus-run.sh"
  if "${SONOBUS_RUN_SCRIPT}" 9<&-; then
    log "SonoBus restarted successfully."
  else
    log "SonoBus restart failed (exit $?); will retry next cycle."
  fi
}

log "Watchdog started (interval=${WATCHDOG_INTERVAL}s, min_restart=${WATCHDOG_MIN_RESTART_INTERVAL}s)."

last_restart=0
suite_gone_count=0

while true; do
  sleep "${WATCHDOG_INTERVAL}"

  if ! suite_is_running; then
    suite_gone_count=$(( suite_gone_count + 1 ))
    if (( suite_gone_count >= WATCHDOG_SUITE_GONE_THRESHOLD )); then
      log "Core DSP modules missing for ${suite_gone_count} consecutive checks; watchdog exiting."
      exit 0
    fi
    log "Core DSP modules not visible (output:out_0 missing); check ${suite_gone_count}/${WATCHDOG_SUITE_GONE_THRESHOLD}."
    continue
  fi
  suite_gone_count=0

  if ! sonobus_port_exists; then
    now="$(date +%s)"
    elapsed=$(( now - last_restart ))
    if (( elapsed < WATCHDOG_MIN_RESTART_INTERVAL )); then
      log "SonoBus is down but last restart was ${elapsed}s ago (min ${WATCHDOG_MIN_RESTART_INTERVAL}s); waiting."
    else
      last_restart="${now}"
      restart_sonobus
    fi
  fi
done
