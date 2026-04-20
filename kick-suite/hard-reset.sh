#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_DIR="${SCRIPT_DIR}/.runlogs"

MAIN_BIN="${REPO_ROOT}/utilities/main"
KICK_MIX_BIN="${REPO_ROOT}/utilities/kick-mix"
VOICE_SPECTRAL_GOVERNANCE_BIN="${REPO_ROOT}/spectral-governance/voice-spectral-governance"
SEND_VOICE_SPECTRAL_GOVERNANCE_BIN="${REPO_ROOT}/spectral-governance/send-voice-spectral-governance"
VOICE_SATURATION_BIN="${REPO_ROOT}/saturation/voice-saturation"
SEND_VOICE_SATURATION_BIN="${REPO_ROOT}/saturation/send-voice-saturation"
OUTPUT_BIN="${REPO_ROOT}/utilities/output"
KICK_909_BIN="${REPO_ROOT}/kicks/909"
KICK_808_BIN="${REPO_ROOT}/kicks/808"
SONOBUS_BIN="${SONOBUS_BIN:-$(command -v sonobus || true)}"
AOO_SERVER_BIN="${AOO_SERVER_BIN:-${SCRIPT_DIR}/bin/aooserver}"
WATCHDOG_SCRIPT="${SCRIPT_DIR}/watchdog.sh"

mkdir -p "${LOG_DIR}"

kill_pattern() {
  local pattern="$1"
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
  kill_pattern "${OUTPUT_BIN}"
  kill_pattern "${KICK_909_BIN}"
  kill_pattern "${KICK_808_BIN}"
}

restart_user_audio_services() {
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "systemctl is required for audio service restart." >&2
    return 1
  fi

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

  echo "Timed out waiting for PipeWire after restart." >&2
  return 1
}

stale_suite_ports_exist() {
  pw-link -o 2>/dev/null | grep -Eq '^(main|909|808|kick-mix|voice-spectral-governance|send-voice-spectral-governance|voice-saturation|send-voice-saturation|output|SonoBus):'
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

if stale_suite_ports_exist; then
  echo "Warning: stale KickSuite ports are still visible after audio restart." >&2
  pw-link -o | grep -E '^(main|909|808|kick-mix|voice-spectral-governance|send-voice-spectral-governance|voice-saturation|send-voice-saturation|output|SonoBus):' >&2 || true
else
  echo "KickSuite hard reset complete; no stale suite ports remain."
fi
