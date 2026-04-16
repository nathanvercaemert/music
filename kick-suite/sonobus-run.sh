#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_DIR="${SCRIPT_DIR}/.runlogs"
SETUP_FILE="${SONOBUS_SETUP:-${SCRIPT_DIR}/sonobus/909-high-quality.xml}"
ENV_FILE="${SONOBUS_ENV_FILE:-${SCRIPT_DIR}/sonobus.env}"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

SONOBUS_BIN="${SONOBUS_BIN:-$(command -v sonobus || true)}"
SONOBUS_GROUP="${SONOBUS_GROUP:-}"
SONOBUS_USERNAME="${SONOBUS_USERNAME:-music}"
SONOBUS_PASSWORD="${SONOBUS_PASSWORD:-}"
SONOBUS_SERVER="${SONOBUS_SERVER:-aoo.sonobus.net:10998}"
AOO_SERVER_BIN="${AOO_SERVER_BIN:-${SCRIPT_DIR}/bin/aooserver}"
AOO_SERVER_LOG_DIR="${AOO_SERVER_LOG_DIR:-${LOG_DIR}}"
AOO_SERVER_START_TIMEOUT="${AOO_SERVER_START_TIMEOUT:-5}"
SONOBUS_DISABLE_RUSTDESK="${SONOBUS_DISABLE_RUSTDESK:-1}"
SONOBUS_KILL_RUSTDESK="${SONOBUS_KILL_RUSTDESK:-0}"
SONOBUS_START_RETRIES="${SONOBUS_START_RETRIES:-3}"
SONOBUS_ALLOW_SETUP_FALLBACK="${SONOBUS_ALLOW_SETUP_FALLBACK:-1}"
SONOBUS_PREFER_SAVED_SETUP="${SONOBUS_PREFER_SAVED_SETUP:-0}"
PIPEWIRE_LATENCY_VALUE="${PIPEWIRE_LATENCY_VALUE:-2048/48000}"

DISPLAY_VALUE="${DISPLAY_VALUE:-:0}"
XAUTHORITY_VALUE="${XAUTHORITY_VALUE:-${HOME}/.Xauthority}"
XDG_RUNTIME_DIR_VALUE="${XDG_RUNTIME_DIR_VALUE:-/run/user/$(id -u)}"

RUSTDESK_IN_FL="${RUSTDESK_IN_FL:-RustDesk:input_FL}"
RUSTDESK_IN_FR="${RUSTDESK_IN_FR:-RustDesk:input_FR}"
RUSTDESK_MON_FL="${RUSTDESK_MON_FL:-alsa_output.platform-fe00b840.mailbox.stereo-fallback:monitor_FL}"
RUSTDESK_MON_FR="${RUSTDESK_MON_FR:-alsa_output.platform-fe00b840.mailbox.stereo-fallback:monitor_FR}"
PLAYBACK_FL="${PLAYBACK_FL:-alsa_output.platform-fe00b840.mailbox.stereo-fallback:playback_FL}"
PLAYBACK_FR="${PLAYBACK_FR:-alsa_output.platform-fe00b840.mailbox.stereo-fallback:playback_FR}"

mkdir -p "${LOG_DIR}"

if [[ -z "${SONOBUS_BIN}" ]]; then
  echo "sonobus is required but not installed." >&2
  exit 1
fi

if [[ -z "${SONOBUS_GROUP}" ]]; then
  echo "SONOBUS_GROUP is required." >&2
  exit 1
fi

if [[ ! -f "${SETUP_FILE}" ]]; then
  echo "SonoBus setup file not found: ${SETUP_FILE}" >&2
  exit 1
fi

if ! command -v pw-jack >/dev/null 2>&1; then
  echo "pw-jack is required but not installed." >&2
  exit 1
fi

if ! command -v pw-link >/dev/null 2>&1; then
  echo "pw-link is required but not installed." >&2
  exit 1
fi

server_host="${SONOBUS_SERVER%:*}"
server_port="${SONOBUS_SERVER##*:}"
sonobus_connect_host="${server_host}"

if [[ -z "${server_host}" || -z "${server_port}" || "${server_host}" == "${SONOBUS_SERVER}" ]]; then
  echo "SONOBUS_SERVER must use host:port syntax: ${SONOBUS_SERVER}" >&2
  exit 1
fi

set_default_audio_source() {
  local node_name="$1"

  if ! command -v pw-metadata >/dev/null 2>&1; then
    return
  fi

  pw-metadata -n default 0 default.audio.source "{\"name\":\"${node_name}\"}" >/dev/null 2>&1 || true
}

disconnect_if_linked() {
  local output_port="$1"
  local input_port="$2"
  pw-link -d "${output_port}" "${input_port}" >/dev/null 2>&1 || true
}

connect_if_missing() {
  local output_port="$1"
  local input_port="$2"
  pw-link "${output_port}" "${input_port}" >/dev/null 2>&1 || true
}

port_exists() {
  local port_name="$1"
  pw-link -o 2>/dev/null | grep -Fxq "${port_name}" || pw-link -i 2>/dev/null | grep -Fxq "${port_name}"
}

udp_port_is_listening() {
  local port="$1"

  if command -v ss >/dev/null 2>&1; then
    ss -H -lun 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:|\\])${port}$"
    return $?
  fi

  if command -v netstat >/dev/null 2>&1; then
    netstat -lun 2>/dev/null | awk 'NR > 2 { print $4 }' | grep -Eq "(^|:|\\])${port}$"
    return $?
  fi

  return 1
}

host_matches_local_address() {
  local host="$1"
  local local_address

  case "${host}" in
    localhost|127.0.0.1|::1|0.0.0.0)
      return 0
      ;;
  esac

  if [[ "${host}" == "$(hostname 2>/dev/null || true)" || "${host}" == "$(hostname -f 2>/dev/null || true)" ]]; then
    return 0
  fi

  while read -r local_address; do
    [[ -n "${local_address}" ]] || continue
    if [[ "${host}" == "${local_address}" ]]; then
      return 0
    fi
  done < <(
    {
      hostname -I 2>/dev/null | tr ' ' '\n'
      ip -o addr show up 2>/dev/null | awk '{print $4}' | cut -d/ -f1
    } | sed '/^$/d' | sort -u
  )

  return 1
}

ensure_local_aoo_server() {
  local timeout="${AOO_SERVER_START_TIMEOUT}"
  local delay=0.2
  local tries
  local i

  if ! host_matches_local_address "${server_host}"; then
    return 0
  fi

  # Connecting to the local AOO server via a non-loopback host address is
  # unreliable on this machine; use localhost once we've confirmed the server
  # target is the local host.
  sonobus_connect_host="localhost"

  if [[ ! -x "${AOO_SERVER_BIN}" ]]; then
    echo "Local AOO server requested via ${SONOBUS_SERVER}, but aooserver is not executable: ${AOO_SERVER_BIN}" >&2
    exit 1
  fi

  if udp_port_is_listening "${server_port}"; then
    return 0
  fi

  mkdir -p "${AOO_SERVER_LOG_DIR}"
  setsid -f "${AOO_SERVER_BIN}" -p "${server_port}" -l "${AOO_SERVER_LOG_DIR}" >/dev/null 2>&1 < /dev/null

  tries=$(awk -v timeout="${timeout}" -v delay="${delay}" 'BEGIN { print int((timeout / delay) + 0.5) }')
  if [[ "${tries}" -lt 1 ]]; then
    tries=1
  fi

  for ((i = 0; i < tries; i += 1)); do
    if udp_port_is_listening "${server_port}"; then
      return 0
    fi
    sleep "${delay}"
  done

  echo "Timed out waiting for local aooserver on UDP port ${server_port}." >&2
  exit 1
}

disconnect_module_sinks() {
  local output_port="$1"

  disconnect_if_linked "${output_port}" "${PLAYBACK_FL}"
  disconnect_if_linked "${output_port}" "${PLAYBACK_FR}"
  disconnect_if_linked "${output_port}" "${RUSTDESK_IN_FL}"
  disconnect_if_linked "${output_port}" "${RUSTDESK_IN_FR}"
  disconnect_if_linked "${output_port}" "SonoBus:in_1"
  disconnect_if_linked "${output_port}" "SonoBus:in_2"
}

wait_for_port() {
  local port_name="$1"
  local tries="${2:-50}"
  local delay="${3:-0.2}"
  local i

  for ((i = 0; i < tries; i += 1)); do
    if pw-link -o 2>/dev/null | grep -Fxq "${port_name}" || pw-link -i 2>/dev/null | grep -Fxq "${port_name}"; then
      return 0
    fi
    sleep "${delay}"
  done

  echo "Timed out waiting for port ${port_name}" >&2
  return 1
}

wait_for_optional_port() {
  local port_name="$1"
  local tries="${2:-50}"
  local delay="${3:-0.2}"
  local i

  for ((i = 0; i < tries; i += 1)); do
    if pw-link -o 2>/dev/null | grep -Fxq "${port_name}" || pw-link -i 2>/dev/null | grep -Fxq "${port_name}"; then
      return 0
    fi
    sleep "${delay}"
  done

  return 1
}

stop_sonobus() {
  pkill -f "${SONOBUS_BIN}" || true
}

stop_rustdesk_audio() {
  disconnect_if_linked "${RUSTDESK_MON_FL}" "${RUSTDESK_IN_FL}"
  disconnect_if_linked "${RUSTDESK_MON_FR}" "${RUSTDESK_IN_FR}"

  if [[ "${SONOBUS_KILL_RUSTDESK}" == "1" ]]; then
    pkill -x rustdesk >/dev/null 2>&1 || true
    pkill -f RustDesk >/dev/null 2>&1 || true
  fi
}

start_sonobus() {
  local use_setup="${1:-1}"
  local setup_arg=""

  if [[ "${use_setup}" == "1" ]]; then
    setup_arg="-l '${SETUP_FILE}'"
  fi

  : > "${LOG_DIR}/sonobus.log"
  setsid -f sh -c "env DISPLAY='${DISPLAY_VALUE}' XAUTHORITY='${XAUTHORITY_VALUE}' XDG_RUNTIME_DIR='${XDG_RUNTIME_DIR_VALUE}' PIPEWIRE_LATENCY='${PIPEWIRE_LATENCY_VALUE}' pw-jack '${SONOBUS_BIN}' --headless ${setup_arg} -g '${SONOBUS_GROUP}' -n '${SONOBUS_USERNAME}' ${SONOBUS_PASSWORD:+-p '${SONOBUS_PASSWORD}'} -c '${sonobus_connect_host}:${server_port}' >'${LOG_DIR}/sonobus.log' 2>&1 < /dev/null"
}

sonobus_log_is_healthy() {
  ! grep -Eq "sink not found|channel count 0 out of range" "${LOG_DIR}/sonobus.log"
}

wait_for_healthy_sonobus() {
  wait_for_port "SonoBus:in_1"
  wait_for_port "SonoBus:out_1"
  wait_for_port "SonoBus:out_2"
  wait_for_port "output:out_0"
  wait_for_port "output:out_1"
  wait_for_optional_port "SonoBus:in_2" 15 0.2
  sonobus_log_is_healthy
}

# SonoBus 1.7.x on this host misbehaves when PipeWire has no real default source.
# Pointing the default source at the duplex output node restores stereo JACK inputs.
set_default_audio_source "output"
ensure_local_aoo_server

stop_sonobus
stop_rustdesk_audio

sonobus_started=0
sonobus_started_with_setup=0

setup_modes=(0)
if [[ "${SONOBUS_PREFER_SAVED_SETUP}" == "1" ]]; then
  setup_modes=(1 0)
elif [[ "${SONOBUS_ALLOW_SETUP_FALLBACK}" == "1" ]]; then
  setup_modes=(0 1)
fi

for setup_mode in "${setup_modes[@]}"; do
  if [[ "${setup_mode}" == "1" && "${SONOBUS_ALLOW_SETUP_FALLBACK}" != "1" && "${SONOBUS_PREFER_SAVED_SETUP}" != "1" ]]; then
    continue
  fi

  for ((attempt = 1; attempt <= SONOBUS_START_RETRIES; attempt += 1)); do
    start_sonobus "${setup_mode}"

    if wait_for_healthy_sonobus; then
      sonobus_started=1
      sonobus_started_with_setup="${setup_mode}"
      break 2
    fi

    if [[ "${setup_mode}" == "1" ]]; then
      echo "SonoBus startup attempt ${attempt}/${SONOBUS_START_RETRIES} with setup file failed health checks; retrying." >&2
    else
      echo "SonoBus startup attempt ${attempt}/${SONOBUS_START_RETRIES} without setup file failed health checks; retrying." >&2
    fi
    stop_sonobus
    sleep 1
  done
done

if [[ "${sonobus_started}" != "1" ]]; then
  echo "SonoBus failed health checks after ${SONOBUS_START_RETRIES} attempts." >&2
  echo "Check ${LOG_DIR}/sonobus.log for sink or channel negotiation errors." >&2
  exit 1
fi

sonobus_in_left="SonoBus:in_1"
sonobus_in_right="SonoBus:in_2"
stereo_input_ready=1

if ! port_exists "${sonobus_in_right}"; then
  stereo_input_ready=0
  sonobus_in_right="${sonobus_in_left}"
fi

disconnect_if_linked "SonoBus:out_1" "${PLAYBACK_FL}"
disconnect_if_linked "SonoBus:out_2" "${PLAYBACK_FR}"
disconnect_if_linked "output:out_0" "${RUSTDESK_IN_FL}"
disconnect_if_linked "output:out_1" "${RUSTDESK_IN_FR}"

if [[ "${SONOBUS_DISABLE_RUSTDESK}" == "1" ]]; then
  stop_rustdesk_audio
fi

disconnect_module_sinks "main:out_0"
disconnect_module_sinks "main:out_1"
disconnect_module_sinks "909:out_0"
disconnect_module_sinks "808:out_0"
disconnect_module_sinks "kick-mix:out_0"
  disconnect_module_sinks "voice-spectral-governance:out_0"
disconnect_module_sinks "send-voice-spectral-governance:out_0"
disconnect_module_sinks "voice-saturation:out_0"
disconnect_module_sinks "send-voice-saturation:out_0"

disconnect_if_linked "output:out_0" "SonoBus:in_1"
disconnect_if_linked "output:out_1" "SonoBus:in_1"
disconnect_if_linked "output:out_0" "SonoBus:in_2"
disconnect_if_linked "output:out_1" "SonoBus:in_2"

connect_if_missing "output:out_0" "${sonobus_in_left}"
connect_if_missing "output:out_1" "${sonobus_in_right}"
connect_if_missing "SonoBus:out_1" "${PLAYBACK_FL}"
connect_if_missing "SonoBus:out_2" "${PLAYBACK_FR}"

cat <<EOF
SonoBus started.

Setup:
  ${SETUP_FILE}

Connection:
  group=${SONOBUS_GROUP}
  username=${SONOBUS_USERNAME}
  server=${sonobus_connect_host}:${server_port}

Ports wired:
  output:out_0 -> ${sonobus_in_left}
  output:out_1 -> ${sonobus_in_right}
  SonoBus:out_1 -> ${PLAYBACK_FL}
  SonoBus:out_2 -> ${PLAYBACK_FR}

Log:
  ${LOG_DIR}/sonobus.log
EOF

if [[ "${sonobus_started_with_setup}" != "1" ]]; then
  echo "SonoBus fell back to default headless startup without loading ${SETUP_FILE}." >&2
fi

if [[ "${stereo_input_ready}" != "1" ]]; then
  echo "SonoBus exposed only in_1; using mono input fallback on ${sonobus_in_left}." >&2
fi
