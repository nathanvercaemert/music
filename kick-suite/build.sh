#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

MAIN_DSP="${REPO_ROOT}/utilities/main.dsp"
KICK_MIX_DSP="${REPO_ROOT}/utilities/kick-mix.dsp"
KICK_FILTERS_DSP="${REPO_ROOT}/filters/kick-filters.dsp"
OUTPUT_DSP="${REPO_ROOT}/utilities/output.dsp"
KICK_909_DSP="${REPO_ROOT}/kicks/909.dsp"
KICK_808_DSP="${REPO_ROOT}/kicks/808.dsp"
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

if [[ -z "${FAUST_JACK_COMPILER}" ]]; then
  detect_gui_session
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

need_rebuild() {
  local binary="$1"
  local dsp="$2"
  [[ ! -x "${binary}" || "${binary}" -ot "${dsp}" ]]
}

need_xml_refresh() {
  local xml="$1"
  local dsp="$2"
  [[ ! -f "${xml}" || "${xml}" -ot "${dsp}" ]]
}

refresh_xml() {
  local out_dir="$1"
  local dsp="$2"
  local xml_path="${dsp}.xml"

  if need_xml_refresh "${xml_path}" "${dsp}"; then
    faust -xml -O "${out_dir}" "${dsp}" >/dev/null
  fi
}

build_module() {
  local binary="$1"
  local dsp="$2"
  local out_dir="$3"

  refresh_xml "${out_dir}" "${dsp}"

  if need_rebuild "${binary}" "${dsp}"; then
    "${FAUST_JACK_COMPILER}" "${dsp}"
  fi
}

build_module "${REPO_ROOT}/utilities/main" "${MAIN_DSP}" "${REPO_ROOT}/utilities"
build_module "${REPO_ROOT}/utilities/kick-mix" "${KICK_MIX_DSP}" "${REPO_ROOT}/utilities"
build_module "${REPO_ROOT}/filters/kick-filters" "${KICK_FILTERS_DSP}" "${REPO_ROOT}/filters"
build_module "${REPO_ROOT}/utilities/output" "${OUTPUT_DSP}" "${REPO_ROOT}/utilities"
build_module "${REPO_ROOT}/kicks/909" "${KICK_909_DSP}" "${REPO_ROOT}/kicks"
build_module "${REPO_ROOT}/kicks/808" "${KICK_808_DSP}" "${REPO_ROOT}/kicks"

cat <<EOF
Build complete.

Generated:
  ${REPO_ROOT}/utilities/main
  ${REPO_ROOT}/utilities/kick-mix
  ${REPO_ROOT}/filters/kick-filters
  ${REPO_ROOT}/utilities/output
  ${REPO_ROOT}/kicks/909
  ${REPO_ROOT}/kicks/808

Compiler:
  ${FAUST_JACK_COMPILER}

Next:
  ${SCRIPT_DIR}/run.sh
EOF
