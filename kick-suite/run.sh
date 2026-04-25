#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_DIR="${SCRIPT_DIR}/.runlogs"
LOGGING_LIB="${SCRIPT_DIR}/lib/logging.sh"
BUILD_SCRIPT="${SCRIPT_DIR}/build.sh"
SONOBUS_RUN_SCRIPT="${SCRIPT_DIR}/sonobus-run.sh"
WATCHDOG_SCRIPT="${SCRIPT_DIR}/watchdog.sh"
HARD_RESET_SCRIPT="${SCRIPT_DIR}/hard-reset.sh"
SHOW_WINDOWS_SCRIPT="${SCRIPT_DIR}/show-faust-windows.py"
SHOW_WINDOWS="${SHOW_WINDOWS:-1}"

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
MAIN_DSP="${REPO_ROOT}/utilities/main.dsp"
KICK_MIX_DSP="${REPO_ROOT}/utilities/kick-mix.dsp"
VOICE_SPECTRAL_GOVERNANCE_DSP="${REPO_ROOT}/spectral-governance/voice-spectral-governance.dsp"
SEND_VOICE_SPECTRAL_GOVERNANCE_DSP="${REPO_ROOT}/spectral-governance/send-voice-spectral-governance.dsp"
VOICE_SATURATION_DSP="${REPO_ROOT}/saturation/voice-saturation.dsp"
SEND_VOICE_SATURATION_DSP="${REPO_ROOT}/saturation/send-voice-saturation.dsp"
SATURATION_SPECTRAL_GOVERNANCE_DSP="${REPO_ROOT}/saturation-spectral-governance/saturation-spectral-governance.dsp"
SEND_SATURATION_SPECTRAL_GOVERNANCE_DSP="${REPO_ROOT}/saturation-spectral-governance/send-saturation-spectral-governance.dsp"
OUTPUT_DSP="${REPO_ROOT}/utilities/output.dsp"
KICK_909_DSP="${REPO_ROOT}/kicks/909.dsp"
KICK_808_DSP="${REPO_ROOT}/kicks/808.dsp"
USE_SONOBUS="${USE_SONOBUS:-1}"
USE_CARLA_PATCHBAY="${USE_CARLA_PATCHBAY:-0}"
RECOVER_AUDIO_ON_START="${RECOVER_AUDIO_ON_START:-1}"
AOO_SERVER_BIN="${AOO_SERVER_BIN:-${SCRIPT_DIR}/bin/aooserver}"
SONOBUS_BIN="${SONOBUS_BIN:-$(command -v sonobus || true)}"
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

# shellcheck disable=SC1090
source "${LOGGING_LIB}"
ks_start_new_run
LOG_DIR="$(ks_log_subdir logs)"
mkdir -p "${LOG_DIR}"
ks_event info run suite_start "kick suite launch started" git_sha="$(ks_git_sha)" use_sonobus="${USE_SONOBUS}" recover_audio_on_start="${RECOVER_AUDIO_ON_START}"

log_previous_hard_reset_marker() {
  local marker="${KS_LOG_DIR}/last-hard-reset.env"
  local reset_run_id reset_completed_at reset_completed_epoch reset_result reset_age_s

  [[ -f "${marker}" ]] || return 0

  reset_run_id="$(awk -F= '$1 == "run_id" { print $2; exit }' "${marker}" 2>/dev/null || true)"
  reset_completed_at="$(awk -F= '$1 == "completed_at" { print $2; exit }' "${marker}" 2>/dev/null || true)"
  reset_completed_epoch="$(awk -F= '$1 == "completed_epoch" { print $2; exit }' "${marker}" 2>/dev/null || true)"
  reset_result="$(awk -F= '$1 == "result" { print $2; exit }' "${marker}" 2>/dev/null || true)"
  reset_age_s="unknown"
  if [[ "${reset_completed_epoch}" =~ ^[0-9]+$ ]]; then
    reset_age_s="$(( $(date +%s) - reset_completed_epoch ))"
  fi

  ks_event info run previous_hard_reset "most recent hard reset marker before this launch" hard_reset_run_id="${reset_run_id:-unknown}" hard_reset_completed_at="${reset_completed_at:-unknown}" hard_reset_age_s="${reset_age_s}" hard_reset_result="${reset_result:-unknown}"
}

log_previous_hard_reset_marker

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

link_required() {
  local output_port="$1"
  local input_port="$2"

  if pw-link "${output_port}" "${input_port}" >/dev/null 2>&1; then
    return 0
  fi

  ks_event error run link_failed "required link failed" output_port="${output_port}" input_port="${input_port}"
  ks_snapshot link_failed "${output_port} -> ${input_port}"
  return 1
}

restart_user_audio_services() {
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "systemctl is required for audio recovery restarts." >&2
    return 1
  fi

  systemctl --user restart wireplumber pipewire pipewire-pulse

  local tries=50
  local delay=0.2
  local i
  for ((i = 0; i < tries; i += 1)); do
    if pw-link -o >/dev/null 2>&1; then
      return 0
    fi
    sleep "${delay}"
  done

  echo "Timed out waiting for PipeWire after user service restart." >&2
  return 1
}

stop_existing_suite() {
  pkill -f "${WATCHDOG_SCRIPT}" || true
  [[ -n "${SONOBUS_BIN}" ]] && pkill -f "${SONOBUS_BIN}" || true
  pkill -f "${AOO_SERVER_BIN}" || true
  pkill -f "${MAIN_BIN}" || true
  pkill -f "${KICK_MIX_BIN}" || true
  pkill -f "${VOICE_SPECTRAL_GOVERNANCE_BIN}" || true
  pkill -f "${SEND_VOICE_SPECTRAL_GOVERNANCE_BIN}" || true
  pkill -f "${VOICE_SATURATION_BIN}" || true
  pkill -f "${SEND_VOICE_SATURATION_BIN}" || true
  pkill -f "${SATURATION_SPECTRAL_GOVERNANCE_BIN}" || true
  pkill -f "${SEND_SATURATION_SPECTRAL_GOVERNANCE_BIN}" || true
  pkill -f "${OUTPUT_BIN}" || true
  pkill -f "${KICK_909_BIN}" || true
  pkill -f "${KICK_808_BIN}" || true
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
  ks_event info run client_launch "launching DSP client" binary="${binary}" log_file="${log_file}" args="$*"
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

if need_binary "${MAIN_BIN}" "${MAIN_DSP}" || need_binary "${KICK_MIX_BIN}" "${KICK_MIX_DSP}" || need_binary "${VOICE_SPECTRAL_GOVERNANCE_BIN}" "${VOICE_SPECTRAL_GOVERNANCE_DSP}" || need_binary "${SEND_VOICE_SPECTRAL_GOVERNANCE_BIN}" "${SEND_VOICE_SPECTRAL_GOVERNANCE_DSP}" || need_binary "${VOICE_SATURATION_BIN}" "${VOICE_SATURATION_DSP}" || need_binary "${SEND_VOICE_SATURATION_BIN}" "${SEND_VOICE_SATURATION_DSP}" || need_binary "${SATURATION_SPECTRAL_GOVERNANCE_BIN}" "${SATURATION_SPECTRAL_GOVERNANCE_DSP}" || need_binary "${SEND_SATURATION_SPECTRAL_GOVERNANCE_BIN}" "${SEND_SATURATION_SPECTRAL_GOVERNANCE_DSP}" || need_binary "${OUTPUT_BIN}" "${OUTPUT_DSP}" || need_binary "${KICK_909_BIN}" "${KICK_909_DSP}" || need_binary "${KICK_808_BIN}" "${KICK_808_DSP}"; then
  ks_event info run build_required "one or more binaries are missing or older than DSP sources"
  "${BUILD_SCRIPT}"
  ks_event info run build_complete "build script completed"
fi

if [[ "${RECOVER_AUDIO_ON_START}" == "1" && -x "${HARD_RESET_SCRIPT}" ]]; then
  ks_event info run hard_reset_requested "running hard reset before suite launch"
  "${HARD_RESET_SCRIPT}"
elif [[ "${RECOVER_AUDIO_ON_START}" == "1" ]]; then
  ks_event info run audio_recovery_requested "running inline audio service recovery"
  stop_existing_suite
  restart_user_audio_services
fi

detect_gui_session
configure_carla

stop_existing_suite

launch_env=("PIPEWIRE_LATENCY=${PIPEWIRE_LATENCY_VALUE}")
if [[ -n "${GUI_DISPLAY}" && -n "${GUI_XAUTHORITY}" ]]; then
  launch_env=("DISPLAY=${GUI_DISPLAY}" "XAUTHORITY=${GUI_XAUTHORITY}" "PIPEWIRE_LATENCY=${PIPEWIRE_LATENCY_VALUE}")
fi

launch_client "${MAIN_BIN}" "$(ks_component_log_path main.log)"
launch_client "${KICK_MIX_BIN}" "$(ks_component_log_path kick-mix.log)"
launch_client "${VOICE_SPECTRAL_GOVERNANCE_BIN}" "$(ks_component_log_path voice-spectral-governance.log)" -httpd
launch_client "${SEND_VOICE_SPECTRAL_GOVERNANCE_BIN}" "$(ks_component_log_path send-voice-spectral-governance.log)"
launch_client "${VOICE_SATURATION_BIN}" "$(ks_component_log_path voice-saturation.log)" -httpd
launch_client "${SEND_VOICE_SATURATION_BIN}" "$(ks_component_log_path send-voice-saturation.log)"
launch_client "${SATURATION_SPECTRAL_GOVERNANCE_BIN}" "$(ks_component_log_path saturation-spectral-governance.log)" -httpd
launch_client "${SEND_SATURATION_SPECTRAL_GOVERNANCE_BIN}" "$(ks_component_log_path send-saturation-spectral-governance.log)"
launch_client "${OUTPUT_BIN}" "$(ks_component_log_path output.log)"
launch_client "${KICK_909_BIN}" "$(ks_component_log_path 909.log)"
launch_client "${KICK_808_BIN}" "$(ks_component_log_path 808.log)"

sleep 2

disconnect_module_sinks "main:out_0"
disconnect_module_sinks "main:out_1"
disconnect_module_sinks "909:out_0"
disconnect_module_sinks "808:out_0"
disconnect_module_sinks "kick-mix:out_0"
disconnect_module_sinks "voice-spectral-governance:out_0"
disconnect_module_sinks "send-voice-spectral-governance:out_0"
disconnect_module_sinks "voice-saturation:out_0"
disconnect_module_sinks "send-voice-saturation:out_0"
disconnect_module_sinks "saturation-spectral-governance:out_0"
disconnect_module_sinks "send-saturation-spectral-governance:out_0"

if [[ "${SHOW_WINDOWS}" == "1" && -x "${SHOW_WINDOWS_SCRIPT}" ]]; then
  setsid -f env "${launch_env[@]}" sh -c "\"${SHOW_WINDOWS_SCRIPT}\" >/dev/null 2>&1 < /dev/null"
fi

link_required "main:out_0" "909:in_0"
link_required "main:out_1" "808:in_0"
link_required "909:out_0" "kick-mix:in_0"
link_required "808:out_0" "kick-mix:in_1"
link_required "kick-mix:out_0" "voice-spectral-governance:in_0"
link_required "kick-mix:out_0" "send-voice-spectral-governance:in_0"
link_required "voice-spectral-governance:out_0" "send-voice-spectral-governance:in_1"
link_required "send-voice-spectral-governance:out_0" "voice-saturation:in_0"
link_required "send-voice-spectral-governance:out_0" "send-voice-saturation:in_0"
link_required "voice-saturation:out_0" "send-voice-saturation:in_1"
link_required "send-voice-saturation:out_0" "saturation-spectral-governance:in_0"
link_required "send-voice-saturation:out_0" "send-saturation-spectral-governance:in_0"
link_required "saturation-spectral-governance:out_0" "send-saturation-spectral-governance:in_1"
link_required "send-saturation-spectral-governance:out_0" "output:in_0"
ks_event info run graph_linked "core suite graph linked" graph_hash="$(ks_graph_hash)"

if [[ "${USE_SONOBUS}" == "1" ]]; then
  if [[ ! -x "${SONOBUS_RUN_SCRIPT}" ]]; then
    echo "SonoBus helper not found or not executable: ${SONOBUS_RUN_SCRIPT}" >&2
    exit 1
  fi

  "${SONOBUS_RUN_SCRIPT}"

  if [[ -x "${WATCHDOG_SCRIPT}" ]]; then
    watchdog_env=("${launch_env[@]}")
    for var in SONOBUS_BIN SONOBUS_GROUP SONOBUS_USERNAME SONOBUS_PASSWORD SONOBUS_SERVER \
               SONOBUS_ENV_FILE SONOBUS_DISABLE_RUSTDESK SONOBUS_KILL_RUSTDESK \
               SONOBUS_START_RETRIES SONOBUS_ALLOW_SETUP_FALLBACK SONOBUS_PREFER_SAVED_SETUP \
               AOO_SERVER_BIN AOO_SERVER_RESTART \
               WATCHDOG_INTERVAL WATCHDOG_MIN_RESTART_INTERVAL \
               KS_RUN_ID KS_RUN_DIR KS_LOG_DIR KS_RUN_STARTED_EPOCH; do
      [[ -v "${var}" ]] && watchdog_env+=("${var}=${!var}")
    done
    ln -sfn "${LOG_DIR}/watchdog.log" "${SCRIPT_DIR}/.runlogs/watchdog.log" 2>/dev/null || true
    setsid -f env "${watchdog_env[@]}" "${WATCHDOG_SCRIPT}" \
      >>"${LOG_DIR}/watchdog.log" 2>&1 < /dev/null
  fi
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

ks_event info run suite_started "kick suite launch completed" graph_hash="$(ks_graph_hash)" summary="${KS_LOG_DIR}/current-summary.md"
ks_log_health
ks_update_summary

cat <<EOF
Kick suite started.

Ports wired:
  main:out_0 -> 909:in_0
  main:out_1 -> 808:in_0
  909:out_0 -> kick-mix:in_0
  808:out_0 -> kick-mix:in_1
  kick-mix:out_0 -> voice-spectral-governance:in_0
  kick-mix:out_0 -> send-voice-spectral-governance:in_0
  voice-spectral-governance:out_0 -> send-voice-spectral-governance:in_1
  send-voice-spectral-governance:out_0 -> voice-saturation:in_0
  send-voice-spectral-governance:out_0 -> send-voice-saturation:in_0
  voice-saturation:out_0 -> send-voice-saturation:in_1
  send-voice-saturation:out_0 -> saturation-spectral-governance:in_0
  send-voice-saturation:out_0 -> send-saturation-spectral-governance:in_0
  saturation-spectral-governance:out_0 -> send-saturation-spectral-governance:in_1
  send-saturation-spectral-governance:out_0 -> output:in_0
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
  ${LOG_DIR}/send-voice-spectral-governance.log
  ${LOG_DIR}/voice-saturation.log
  ${LOG_DIR}/send-voice-saturation.log
  ${LOG_DIR}/saturation-spectral-governance.log
  ${LOG_DIR}/send-saturation-spectral-governance.log
  ${LOG_DIR}/output.log
  ${LOG_DIR}/909.log
  ${LOG_DIR}/808.log
  ${LOG_DIR}/carla-patchbay.log
  ${LOG_DIR}/watchdog.log
  ${KS_LOG_DIR}/current-summary.md
  ${KS_RUN_DIR}
EOF
