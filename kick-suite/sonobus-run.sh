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
SONOBUS_DISABLE_RUSTDESK="${SONOBUS_DISABLE_RUSTDESK:-1}"

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

pkill -f "${SONOBUS_BIN}" || true

setsid -f sh -c "env DISPLAY='${DISPLAY_VALUE}' XAUTHORITY='${XAUTHORITY_VALUE}' XDG_RUNTIME_DIR='${XDG_RUNTIME_DIR_VALUE}' pw-jack '${SONOBUS_BIN}' --headless -l '${SETUP_FILE}' -g '${SONOBUS_GROUP}' -n '${SONOBUS_USERNAME}' ${SONOBUS_PASSWORD:+-p '${SONOBUS_PASSWORD}'} -c '${SONOBUS_SERVER}' >'${LOG_DIR}/sonobus.log' 2>&1 < /dev/null"

wait_for_port "SonoBus:in_1"
wait_for_port "SonoBus:out_1"
wait_for_port "SonoBus:out_2"
wait_for_port "909:out_0"
wait_for_port "909:out_1"

sonobus_in_left="SonoBus:in_1"
sonobus_in_right="SonoBus:in_2"
stereo_input_ready=1

if ! wait_for_optional_port "${sonobus_in_right}" 15 0.2; then
  stereo_input_ready=0
  sonobus_in_right="${sonobus_in_left}"
fi

disconnect_if_linked "SonoBus:out_1" "${PLAYBACK_FL}"
disconnect_if_linked "SonoBus:out_2" "${PLAYBACK_FR}"
disconnect_if_linked "909:out_0" "${RUSTDESK_IN_FL}"
disconnect_if_linked "909:out_1" "${RUSTDESK_IN_FR}"

if [[ "${SONOBUS_DISABLE_RUSTDESK}" == "1" ]]; then
  disconnect_if_linked "${RUSTDESK_MON_FL}" "${RUSTDESK_IN_FL}"
  disconnect_if_linked "${RUSTDESK_MON_FR}" "${RUSTDESK_IN_FR}"
fi

disconnect_if_linked "909:out_0" "SonoBus:in_1"
disconnect_if_linked "909:out_1" "SonoBus:in_1"
disconnect_if_linked "909:out_0" "SonoBus:in_2"
disconnect_if_linked "909:out_1" "SonoBus:in_2"

connect_if_missing "909:out_0" "${sonobus_in_left}"
connect_if_missing "909:out_1" "${sonobus_in_right}"
connect_if_missing "SonoBus:out_1" "${PLAYBACK_FL}"
connect_if_missing "SonoBus:out_2" "${PLAYBACK_FR}"

cat <<EOF
SonoBus started.

Setup:
  ${SETUP_FILE}

Connection:
  group=${SONOBUS_GROUP}
  username=${SONOBUS_USERNAME}
  server=${SONOBUS_SERVER}

Ports wired:
  909:out_0 -> ${sonobus_in_left}
  909:out_1 -> ${sonobus_in_right}
  SonoBus:out_1 -> ${PLAYBACK_FL}
  SonoBus:out_2 -> ${PLAYBACK_FR}

Log:
  ${LOG_DIR}/sonobus.log
EOF

if [[ "${stereo_input_ready}" != "1" ]]; then
  echo "SonoBus exposed only in_1; using mono input fallback on ${sonobus_in_left}." >&2
fi
