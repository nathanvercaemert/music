#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_DIR="${SCRIPT_DIR}/.runlogs"
LOGGING_LIB="${SCRIPT_DIR}/lib/logging.sh"

# shellcheck disable=SC1090
source "${LOGGING_LIB}"
ks_use_current_or_new
LOG_DIR="$(ks_log_subdir logs)"

MAIN_BIN="${REPO_ROOT}/utilities/main"
KICK_MIX_BIN="${REPO_ROOT}/utilities/kick-mix"
VOICE_SPECTRAL_GOVERNANCE_BIN="${REPO_ROOT}/spectral-governance/voice-spectral-governance"
SEND_VOICE_SPECTRAL_GOVERNANCE_BIN="${REPO_ROOT}/spectral-governance/send-voice-spectral-governance"
VOICE_SATURATION_BIN="${REPO_ROOT}/saturation/voice-saturation"
SEND_VOICE_SATURATION_BIN="${REPO_ROOT}/saturation/send-voice-saturation"
SATURATION_SPECTRAL_GOVERNANCE_BIN="${REPO_ROOT}/saturation-spectral-governance/saturation-spectral-governance"
SEND_SATURATION_SPECTRAL_GOVERNANCE_BIN="${REPO_ROOT}/saturation-spectral-governance/send-saturation-spectral-governance"
OUTPUT_BIN="${REPO_ROOT}/utilities/output"
KICK_909_BIN="${REPO_ROOT}/kicks/909"
KICK_808_BIN="${REPO_ROOT}/kicks/808"
SONOBUS_BIN="${SONOBUS_BIN:-$(command -v sonobus || true)}"
AOO_SERVER_BIN="${AOO_SERVER_BIN:-${SCRIPT_DIR}/bin/aooserver}"
WATCHDOG_SCRIPT="${SCRIPT_DIR}/watchdog.sh"

mkdir -p "${LOG_DIR}"
ks_event info hard-reset hard_reset_start "KickSuite hard reset started"

write_hard_reset_marker() {
  local result="$1"
  local marker="${KS_LOG_DIR}/last-hard-reset.env"

  {
    printf 'run_id=%s\n' "${KS_RUN_ID}"
    printf 'completed_at=%s\n' "$(ks_now)"
    printf 'completed_epoch=%s\n' "$(date +%s)"
    printf 'result=%s\n' "${result}"
    printf 'git_sha=%s\n' "$(ks_git_sha)"
    printf 'git_dirty=%s\n' "$(ks_git_dirty)"
  } > "${marker}" 2>/dev/null || true
}

kill_pattern() {
  local pattern="$1"
  if pgrep -f "${pattern}" >/dev/null 2>&1; then
    ks_event info hard-reset kill_process "killing matching process" pattern="${pattern}"
  fi
  pkill -f "${pattern}" >/dev/null 2>&1 || true
}

wait_until_gone() {
  local pattern="$1"
  local tries="${2:-50}"
  local delay="${3:-0.1}"
  local i

  for ((i = 0; i < tries; i += 1)); do
    if ! pgrep -f "${pattern}" >/dev/null 2>&1; then
      return 0
    fi
    sleep "${delay}"
  done

  ks_event warn hard-reset process_still_running "process pattern still visible after wait" pattern="${pattern}"
  return 1
}

stop_suite_processes() {
  kill_pattern "${WATCHDOG_SCRIPT}"
  [[ -n "${SONOBUS_BIN}" ]] && kill_pattern "${SONOBUS_BIN}"
  kill_pattern "${AOO_SERVER_BIN}"
  kill_pattern "${MAIN_BIN}"
  kill_pattern "${KICK_MIX_BIN}"
  kill_pattern "${VOICE_SPECTRAL_GOVERNANCE_BIN}"
  kill_pattern "${SEND_VOICE_SPECTRAL_GOVERNANCE_BIN}"
  kill_pattern "${VOICE_SATURATION_BIN}"
  kill_pattern "${SEND_VOICE_SATURATION_BIN}"
  kill_pattern "${SATURATION_SPECTRAL_GOVERNANCE_BIN}"
  kill_pattern "${SEND_SATURATION_SPECTRAL_GOVERNANCE_BIN}"
  kill_pattern "${OUTPUT_BIN}"
  kill_pattern "${KICK_909_BIN}"
  kill_pattern "${KICK_808_BIN}"
}

restart_user_audio_services() {
  if ! command -v systemctl >/dev/null 2>&1; then
    ks_event error hard-reset missing_dependency "systemctl is required for audio service restart"
    echo "systemctl is required for audio service restart." >&2
    return 1
  fi

  ks_event info hard-reset audio_services_restart "restarting user audio services"
  systemctl --user restart wireplumber pipewire pipewire-pulse
}

wait_for_pipewire() {
  local tries=50
  local delay=0.2
  local i

  for ((i = 0; i < tries; i += 1)); do
    if pw-link -o >/dev/null 2>&1; then
      return 0
    fi
    sleep "${delay}"
  done

  ks_event error hard-reset pipewire_wait_timeout "timed out waiting for PipeWire after restart"
  ks_snapshot pipewire_wait_timeout "PipeWire did not answer pw-link after restart"
  echo "Timed out waiting for PipeWire after restart." >&2
  return 1
}

stale_suite_ports_exist() {
  pw-link -o 2>/dev/null | grep -Eq '^(main|909|808|kick-mix|voice-spectral-governance|send-voice-spectral-governance|voice-saturation|send-voice-saturation|saturation-spectral-governance|send-saturation-spectral-governance|output|SonoBus):'
}

stop_suite_processes

for pattern in \
  "${WATCHDOG_SCRIPT}" \
  "${MAIN_BIN}" \
  "${KICK_MIX_BIN}" \
  "${VOICE_SPECTRAL_GOVERNANCE_BIN}" \
  "${SEND_VOICE_SPECTRAL_GOVERNANCE_BIN}" \
  "${VOICE_SATURATION_BIN}" \
  "${SEND_VOICE_SATURATION_BIN}" \
  "${SATURATION_SPECTRAL_GOVERNANCE_BIN}" \
  "${SEND_SATURATION_SPECTRAL_GOVERNANCE_BIN}" \
  "${OUTPUT_BIN}" \
  "${KICK_909_BIN}" \
  "${KICK_808_BIN}" \
  "${AOO_SERVER_BIN}"
do
  wait_until_gone "${pattern}" || true
done

if [[ -n "${SONOBUS_BIN}" ]]; then
  wait_until_gone "${SONOBUS_BIN}" || true
fi

restart_user_audio_services
wait_for_pipewire

reset_result="clean"
if stale_suite_ports_exist; then
  reset_result="stale_ports"
  ks_event warn hard-reset stale_ports "stale KickSuite ports remain after audio restart"
  ks_snapshot stale_ports "stale ports visible after audio restart"
  echo "Warning: stale KickSuite ports are still visible after audio restart." >&2
  pw-link -o | grep -E '^(main|909|808|kick-mix|voice-spectral-governance|send-voice-spectral-governance|voice-saturation|send-voice-saturation|saturation-spectral-governance|send-saturation-spectral-governance|output|SonoBus):' >&2 || true
else
  ks_event info hard-reset hard_reset_complete "hard reset complete; no stale suite ports remain"
  echo "KickSuite hard reset complete; no stale suite ports remain."
fi

write_hard_reset_marker "${reset_result}"
ks_log_health
ks_update_summary
