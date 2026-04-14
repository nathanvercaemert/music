#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_DIR="${SCRIPT_DIR}/.runlogs"
BUILD_SCRIPT="${SCRIPT_DIR}/build.sh"
SONOBUS_RUN_SCRIPT="${SCRIPT_DIR}/sonobus-run.sh"
SHOW_WINDOWS_SCRIPT="${SCRIPT_DIR}/show-faust-windows.py"
SHOW_WINDOWS="${SHOW_WINDOWS:-1}"

MAIN_BIN="${REPO_ROOT}/utilities/main"
KICK_MIX_BIN="${REPO_ROOT}/utilities/kick-mix"
VOICE_SPECTRAL_GOVERNANCE_BIN="${REPO_ROOT}/spectral-governance/voice-spectral-governance"
ALT_VOICE_SPECTRAL_GOVERNANCE_BIN="${REPO_ROOT}/spectral-governance/alt-voice-spectral-governance"
OUTPUT_BIN="${REPO_ROOT}/utilities/output"
KICK_909_BIN="${REPO_ROOT}/kicks/909"
KICK_808_BIN="${REPO_ROOT}/kicks/808"
MAIN_DSP="${REPO_ROOT}/utilities/main.dsp"
KICK_MIX_DSP="${REPO_ROOT}/utilities/kick-mix.dsp"
VOICE_SPECTRAL_GOVERNANCE_DSP="${REPO_ROOT}/spectral-governance/voice-spectral-governance.dsp"
ALT_VOICE_SPECTRAL_GOVERNANCE_DSP="${REPO_ROOT}/spectral-governance/alt-voice-spectral-governance.dsp"
OUTPUT_DSP="${REPO_ROOT}/utilities/output.dsp"
KICK_909_DSP="${REPO_ROOT}/kicks/909.dsp"
KICK_808_DSP="${REPO_ROOT}/kicks/808.dsp"
USE_SONOBUS="${USE_SONOBUS:-1}"
USE_CARLA_PATCHBAY="${USE_CARLA_PATCHBAY:-0}"
GUI_DISPLAY="${GUI_DISPLAY:-${DISPLAY:-}}"
GUI_XAUTHORITY="${GUI_XAUTHORITY:-${XAUTHORITY:-}}"
GUI_DISPLAY_FALLBACK="${GUI_DISPLAY_FALLBACK:-:0}"
GUI_XAUTHORITY_FALLBACK="${GUI_XAUTHORITY_FALLBACK:-${HOME}/.Xauthority}"
PIPEWIRE_LATENCY_VALUE="${PIPEWIRE_LATENCY_VALUE:-2048/48000}"

PLAYBACK_FL="${PLAYBACK_FL:-alsa_output.platform-fe00b840.mailbox.stereo-fallback:playback_FL}"
PLAYBACK_FR="${PLAYBACK_FR:-alsa_output.platform-fe00b840.mailbox.stereo-fallback:playback_FR}"
RUSTDESK_IN_FL="${RUSTDESK_IN_FL:-RustDesk:input_FL}"
RUSTDESK_IN_FR="${RUSTDESK_IN_FR:-RustDesk:input_FR}"
RUSTDESK_MON_FL="${RUSTDESK_MON_FL:-RustDesk:monitor_FL}"
RUSTDESK_MON_FR="${RUSTDESK_MON_FR:-RustDesk:monitor_FR}"
CARLA_ROOT="${CARLA_ROOT:-${HOME}/src/carla}"
CARLA_PATCHBAY="${CARLA_PATCHBAY:-}"
CARLA_LD_LIBRARY_PATH="${CARLA_LD_LIBRARY_PATH:-}"
CARLA_PYTHONPATH="${CARLA_PYTHONPATH:-}"

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

  if [[ -z "${GUI_DISPLAY}" ]]; then
    GUI_DISPLAY="${GUI_DISPLAY_FALLBACK}"
  fi

  if [[ -z "${GUI_XAUTHORITY}" && -f "${GUI_XAUTHORITY_FALLBACK}" ]]; then
    GUI_XAUTHORITY="${GUI_XAUTHORITY_FALLBACK}"
  fi
}

need_binary() {
  local binary="$1"
  local dsp="$2"
  [[ ! -x "${binary}" || "${binary}" -ot "${dsp}" ]]
}

port_exists() {
  local port_name="$1"
  pw-link -o 2>/dev/null | grep -Fxq "${port_name}" || pw-link -i 2>/dev/null | grep -Fxq "${port_name}"
}

connect_if_missing() {
  local output_port="$1"
  local input_port="$2"
  pw-link "${output_port}" "${input_port}" >/dev/null 2>&1 || true
}

disconnect_if_linked() {
  local output_port="$1"
  local input_port="$2"
  pw-link -d "${output_port}" "${input_port}" >/dev/null 2>&1 || true
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

launch_client() {
  local binary="$1"
  local log_file="$2"
  shift 2
  setsid -f env "${launch_env[@]}" pw-jack "${binary}" "$@" >"${log_file}" 2>&1 < /dev/null
}

configure_carla() {
  local candidate

  if [[ -n "${CARLA_PATCHBAY}" ]]; then
    return
  fi

  for candidate in \
    "${CARLA_ROOT}/source/frontend/carla-patchbay" \
    "${CARLA_ROOT}/data/carla-patchbay" \
    "$(command -v carla-patchbay 2>/dev/null || true)"
  do
    [[ -n "${candidate}" && -x "${candidate}" ]] || continue
    CARLA_PATCHBAY="${candidate}"
    break
  done

  case "${CARLA_PATCHBAY}" in
    "${CARLA_ROOT}/source/frontend/"*)
      CARLA_LD_LIBRARY_PATH="${CARLA_LD_LIBRARY_PATH:-${CARLA_ROOT}/bin}"
      CARLA_PYTHONPATH="${CARLA_PYTHONPATH:-${CARLA_ROOT}/source/frontend:${CARLA_ROOT}/bin/resources}"
      ;;
    "${CARLA_ROOT}/data/"*)
      CARLA_LD_LIBRARY_PATH="${CARLA_LD_LIBRARY_PATH:-${CARLA_ROOT}/bin:${CARLA_ROOT}/build/lib}"
      CARLA_PYTHONPATH="${CARLA_PYTHONPATH:-${CARLA_ROOT}/source/frontend:${CARLA_ROOT}/build/lib:${CARLA_ROOT}/data}"
      ;;
    *)
      ;;
  esac
}

launch_carla_patchbay() {
  if [[ "${CARLA_PATCHBAY}" == "${CARLA_ROOT}/source/frontend/"* ]]; then
    setsid -f env "${launch_env[@]}" sh -c "cd \"${CARLA_ROOT}/source/frontend\" && LD_LIBRARY_PATH=\"${CARLA_LD_LIBRARY_PATH:+${CARLA_LD_LIBRARY_PATH}:}\${LD_LIBRARY_PATH:-}\" PYTHONPATH=\"${CARLA_PYTHONPATH:+${CARLA_PYTHONPATH}:}\${PYTHONPATH:-}\" \"${CARLA_PATCHBAY}\" >\"${LOG_DIR}/carla-patchbay.log\" 2>&1 < /dev/null"
  else
    setsid -f env "${launch_env[@]}" sh -c "LD_LIBRARY_PATH=\"${CARLA_LD_LIBRARY_PATH:+${CARLA_LD_LIBRARY_PATH}:}\${LD_LIBRARY_PATH:-}\" PYTHONPATH=\"${CARLA_PYTHONPATH:+${CARLA_PYTHONPATH}:}\${PYTHONPATH:-}\" \"${CARLA_PATCHBAY}\" --with-libprefix=\"${CARLA_ROOT}\" >\"${LOG_DIR}/carla-patchbay.log\" 2>&1 < /dev/null"
  fi
}

if need_binary "${MAIN_BIN}" "${MAIN_DSP}" || need_binary "${KICK_MIX_BIN}" "${KICK_MIX_DSP}" || need_binary "${VOICE_SPECTRAL_GOVERNANCE_BIN}" "${VOICE_SPECTRAL_GOVERNANCE_DSP}" || need_binary "${ALT_VOICE_SPECTRAL_GOVERNANCE_BIN}" "${ALT_VOICE_SPECTRAL_GOVERNANCE_DSP}" || need_binary "${OUTPUT_BIN}" "${OUTPUT_DSP}" || need_binary "${KICK_909_BIN}" "${KICK_909_DSP}" || need_binary "${KICK_808_BIN}" "${KICK_808_DSP}"; then
  "${BUILD_SCRIPT}"
fi

detect_gui_session
configure_carla

pkill -f "${MAIN_BIN}" || true
pkill -f "${KICK_MIX_BIN}" || true
pkill -f "${VOICE_SPECTRAL_GOVERNANCE_BIN}" || true
pkill -f "${ALT_VOICE_SPECTRAL_GOVERNANCE_BIN}" || true
pkill -f "${OUTPUT_BIN}" || true
pkill -f "${KICK_909_BIN}" || true
pkill -f "${KICK_808_BIN}" || true

launch_env=("PIPEWIRE_LATENCY=${PIPEWIRE_LATENCY_VALUE}")
if [[ -n "${GUI_DISPLAY}" && -n "${GUI_XAUTHORITY}" ]]; then
  launch_env=("DISPLAY=${GUI_DISPLAY}" "XAUTHORITY=${GUI_XAUTHORITY}" "PIPEWIRE_LATENCY=${PIPEWIRE_LATENCY_VALUE}")
fi

launch_client "${MAIN_BIN}" "${LOG_DIR}/main.log"
launch_client "${KICK_MIX_BIN}" "${LOG_DIR}/kick-mix.log"
launch_client "${VOICE_SPECTRAL_GOVERNANCE_BIN}" "${LOG_DIR}/voice-spectral-governance.log" -httpd
launch_client "${ALT_VOICE_SPECTRAL_GOVERNANCE_BIN}" "${LOG_DIR}/alt-voice-spectral-governance.log"
launch_client "${OUTPUT_BIN}" "${LOG_DIR}/output.log"
launch_client "${KICK_909_BIN}" "${LOG_DIR}/909.log"
launch_client "${KICK_808_BIN}" "${LOG_DIR}/808.log"

sleep 2

disconnect_module_sinks "main:out_0"
disconnect_module_sinks "main:out_1"
disconnect_module_sinks "909:out_0"
disconnect_module_sinks "808:out_0"
disconnect_module_sinks "kick-mix:out_0"
disconnect_module_sinks "voice-spectral-governance:out_0"
disconnect_module_sinks "alt-voice-spectral-governance:out_0"

if [[ "${SHOW_WINDOWS}" == "1" && -x "${SHOW_WINDOWS_SCRIPT}" ]]; then
  setsid -f env "${launch_env[@]}" sh -c "\"${SHOW_WINDOWS_SCRIPT}\" >/dev/null 2>&1 < /dev/null"
fi

pw-link "main:out_0" "909:in_0"
pw-link "main:out_1" "808:in_0"
pw-link "909:out_0" "kick-mix:in_0"
pw-link "808:out_0" "kick-mix:in_1"
pw-link "kick-mix:out_0" "voice-spectral-governance:in_0"
pw-link "kick-mix:out_0" "alt-voice-spectral-governance:in_0"
pw-link "voice-spectral-governance:out_0" "alt-voice-spectral-governance:in_1"
pw-link "alt-voice-spectral-governance:out_0" "output:in_0"

if [[ "${USE_SONOBUS}" == "1" ]]; then
  if [[ ! -x "${SONOBUS_RUN_SCRIPT}" ]]; then
    echo "SonoBus helper not found or not executable: ${SONOBUS_RUN_SCRIPT}" >&2
    exit 1
  fi

  "${SONOBUS_RUN_SCRIPT}"
else
  connect_if_missing "output:out_0" "${PLAYBACK_FL}"
  connect_if_missing "output:out_1" "${PLAYBACK_FR}"

  if port_exists "${RUSTDESK_IN_FL}" && port_exists "${RUSTDESK_IN_FR}"; then
    disconnect_if_linked "${RUSTDESK_MON_FL}" "${RUSTDESK_IN_FL}"
    disconnect_if_linked "${RUSTDESK_MON_FR}" "${RUSTDESK_IN_FR}"
    connect_if_missing "output:out_0" "${RUSTDESK_IN_FL}"
    connect_if_missing "output:out_1" "${RUSTDESK_IN_FR}"
  fi
fi

if [[ "${USE_CARLA_PATCHBAY}" == "1" && -x "${CARLA_PATCHBAY}" ]]; then
  pkill -f "${CARLA_PATCHBAY}" || true
  launch_carla_patchbay
fi

cat <<EOF
Kick suite started.

Ports wired:
  main:out_0 -> 909:in_0
  main:out_1 -> 808:in_0
  909:out_0 -> kick-mix:in_0
  808:out_0 -> kick-mix:in_1
  kick-mix:out_0 -> voice-spectral-governance:in_0
  kick-mix:out_0 -> alt-voice-spectral-governance:in_0
  voice-spectral-governance:out_0 -> alt-voice-spectral-governance:in_1
  alt-voice-spectral-governance:out_0 -> output:in_0
$(if [[ "${USE_SONOBUS}" == "1" ]]; then
    cat <<'EOT'
  output outputs -> SonoBus inputs
  SonoBus:out_1 -> playback_FL
  SonoBus:out_2 -> playback_FR
EOT
  else
    cat <<'EOT'
  output:out_0 -> playback_FL
  output:out_1 -> playback_FR
EOT
  fi)

Logs:
  ${LOG_DIR}/main.log
  ${LOG_DIR}/kick-mix.log
  ${LOG_DIR}/voice-spectral-governance.log
  ${LOG_DIR}/alt-voice-spectral-governance.log
  ${LOG_DIR}/output.log
  ${LOG_DIR}/909.log
  ${LOG_DIR}/808.log
  ${LOG_DIR}/carla-patchbay.log
EOF
