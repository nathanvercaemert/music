#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_DIR="${SCRIPT_DIR}/.runlogs"
BUILD_SCRIPT="${SCRIPT_DIR}/build.sh"
SONOBUS_RUN_SCRIPT="${SCRIPT_DIR}/sonobus-run.sh"

MAIN_BIN="${REPO_ROOT}/utilities/main"
KICK_BIN="${REPO_ROOT}/kicks/909"
MAIN_DSP="${REPO_ROOT}/utilities/main.dsp"
KICK_DSP="${REPO_ROOT}/kicks/909.dsp"
USE_SONOBUS="${USE_SONOBUS:-1}"
GUI_DISPLAY="${GUI_DISPLAY:-${DISPLAY:-}}"
GUI_XAUTHORITY="${GUI_XAUTHORITY:-${XAUTHORITY:-}}"

CARLA_ROOT="${HOME}/src/carla"
CARLA_PATCHBAY="${CARLA_ROOT}/source/frontend/carla-patchbay"

mkdir -p "${LOG_DIR}"

detect_gui_session() {
  if [[ -n "${GUI_DISPLAY}" && -n "${GUI_XAUTHORITY}" ]]; then
    return
  fi

  local session
  while read -r session; do
    [[ -n "${session}" ]] || continue

    local session_display
    local session_type

    session_display="$(loginctl show-session "${session}" -p Display --value 2>/dev/null || true)"
    session_type="$(loginctl show-session "${session}" -p Type --value 2>/dev/null || true)"

    [[ -n "${session_display}" ]] || continue
    [[ "${session_type}" == "x11" || "${session_type}" == "wayland" ]] || continue

    GUI_DISPLAY="${session_display}"
    if [[ -z "${GUI_XAUTHORITY}" && -f "${HOME}/.Xauthority" ]]; then
      GUI_XAUTHORITY="${HOME}/.Xauthority"
    fi
    return
  done < <(loginctl list-sessions --no-legend 2>/dev/null | awk -v user="${USER}" '$3 == user { print $1 }')
}

need_binary() {
  local binary="$1"
  local dsp="$2"
  [[ ! -x "${binary}" || "${binary}" -ot "${dsp}" ]]
}

if need_binary "${MAIN_BIN}" "${MAIN_DSP}" || need_binary "${KICK_BIN}" "${KICK_DSP}"; then
  "${BUILD_SCRIPT}"
fi

detect_gui_session

pkill -f "${MAIN_BIN}" || true
pkill -f "${KICK_BIN}" || true

launch_env=()
if [[ -n "${GUI_DISPLAY}" && -n "${GUI_XAUTHORITY}" ]]; then
  launch_env=("DISPLAY=${GUI_DISPLAY}" "XAUTHORITY=${GUI_XAUTHORITY}")
fi

setsid -f env "${launch_env[@]}" sh -c "pw-jack \"${MAIN_BIN}\" >\"${LOG_DIR}/main.log\" 2>&1 < /dev/null"
setsid -f env "${launch_env[@]}" sh -c "pw-jack \"${KICK_BIN}\" >\"${LOG_DIR}/909.log\" 2>&1 < /dev/null"

if [[ -x "${CARLA_PATCHBAY}" ]]; then
  pkill -f "${CARLA_PATCHBAY}" || true
  setsid -f env "${launch_env[@]}" sh -c "cd \"${CARLA_ROOT}/source/frontend\" && LD_LIBRARY_PATH=\"${CARLA_ROOT}/bin:\${LD_LIBRARY_PATH:-}\" PYTHONPATH=\"${CARLA_ROOT}/source/frontend:${CARLA_ROOT}/bin/resources\" \"${CARLA_PATCHBAY}\" --with-libprefix=\"${CARLA_ROOT}\" >\"${LOG_DIR}/carla-patchbay.log\" 2>&1 < /dev/null"
fi

sleep 2

pw-link "main:out_0" "909:in_0"

if [[ "${USE_SONOBUS}" == "1" ]]; then
  if [[ ! -x "${SONOBUS_RUN_SCRIPT}" ]]; then
    echo "SonoBus helper not found or not executable: ${SONOBUS_RUN_SCRIPT}" >&2
    exit 1
  fi

  "${SONOBUS_RUN_SCRIPT}"
else
  pw-link "909:out_0" "alsa_output.platform-fe00b840.mailbox.stereo-fallback:playback_FL"
  pw-link "909:out_1" "alsa_output.platform-fe00b840.mailbox.stereo-fallback:playback_FR"
fi

cat <<EOF
Kick suite started.

Ports wired:
  main:out_0 -> 909:in_0
$(if [[ "${USE_SONOBUS}" == "1" ]]; then
    cat <<'EOT'
  909 outputs -> SonoBus inputs
  SonoBus:out_1 -> playback_FL
  SonoBus:out_2 -> playback_FR
EOT
  else
    cat <<'EOT'
  909:out_0 -> playback_FL
  909:out_1 -> playback_FR
EOT
  fi)

Logs:
  ${LOG_DIR}/main.log
  ${LOG_DIR}/909.log
  ${LOG_DIR}/carla-patchbay.log
EOF
