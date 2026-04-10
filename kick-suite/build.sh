#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

MAIN_DSP="${REPO_ROOT}/utilities/main.dsp"
KICK_DSP="${REPO_ROOT}/kicks/909.dsp"
FAUST_JACK_COMPILER="${FAUST_JACK_COMPILER:-}"
GUI_DISPLAY="${GUI_DISPLAY:-${DISPLAY:-}}"
GUI_XAUTHORITY="${GUI_XAUTHORITY:-${XAUTHORITY:-}}"

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

detect_gui_session

if [[ -z "${FAUST_JACK_COMPILER}" ]]; then
  if [[ -n "${GUI_DISPLAY}" && -n "${GUI_XAUTHORITY}" ]]; then
    FAUST_JACK_COMPILER="faust2jack"
  else
    FAUST_JACK_COMPILER="faust2jackconsole"
  fi
fi

if ! command -v pw-jack >/dev/null 2>&1; then
  echo "pw-jack is required but not installed." >&2
  exit 1
fi

if ! command -v "${FAUST_JACK_COMPILER}" >/dev/null 2>&1; then
  echo "${FAUST_JACK_COMPILER} is required but not installed." >&2
  exit 1
fi

cd "${REPO_ROOT}"

faust -xml -O "${REPO_ROOT}/utilities" "${MAIN_DSP}" >/dev/null
faust -xml -O "${REPO_ROOT}/kicks" "${KICK_DSP}" >/dev/null

pw-jack "${FAUST_JACK_COMPILER}" "${MAIN_DSP}"
pw-jack "${FAUST_JACK_COMPILER}" "${KICK_DSP}"

cat <<EOF
Build complete.

Generated:
  ${REPO_ROOT}/utilities/main
  ${REPO_ROOT}/kicks/909

Compiler:
  ${FAUST_JACK_COMPILER}

Next:
  ${SCRIPT_DIR}/run.sh
EOF
