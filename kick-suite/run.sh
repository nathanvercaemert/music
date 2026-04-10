#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_DIR="${SCRIPT_DIR}/.runlogs"
BUILD_SCRIPT="${SCRIPT_DIR}/build.sh"

MAIN_BIN="${REPO_ROOT}/utilities/main"
KICK_BIN="${REPO_ROOT}/kicks/909"
MAIN_DSP="${REPO_ROOT}/utilities/main.dsp"
KICK_DSP="${REPO_ROOT}/kicks/909.dsp"

CARLA_ROOT="${HOME}/src/carla"
CARLA_PATCHBAY="${CARLA_ROOT}/source/frontend/carla-patchbay"

mkdir -p "${LOG_DIR}"

need_binary() {
  local binary="$1"
  local dsp="$2"
  [[ ! -x "${binary}" || "${binary}" -ot "${dsp}" ]]
}

if need_binary "${MAIN_BIN}" "${MAIN_DSP}" || need_binary "${KICK_BIN}" "${KICK_DSP}"; then
  "${BUILD_SCRIPT}"
fi

pkill -f "${MAIN_BIN}" || true
pkill -f "${KICK_BIN}" || true

setsid -f sh -c "pw-jack \"${MAIN_BIN}\" >\"${LOG_DIR}/main.log\" 2>&1 < /dev/null"
setsid -f sh -c "pw-jack \"${KICK_BIN}\" >\"${LOG_DIR}/909.log\" 2>&1 < /dev/null"

if [[ -x "${CARLA_PATCHBAY}" ]]; then
  pkill -f "${CARLA_PATCHBAY}" || true
  setsid -f sh -c "cd \"${CARLA_ROOT}/source/frontend\" && LD_LIBRARY_PATH=\"${CARLA_ROOT}/bin:\${LD_LIBRARY_PATH:-}\" PYTHONPATH=\"${CARLA_ROOT}/source/frontend:${CARLA_ROOT}/bin/resources\" \"${CARLA_PATCHBAY}\" --with-libprefix=\"${CARLA_ROOT}\" >\"${LOG_DIR}/carla-patchbay.log\" 2>&1 < /dev/null"
fi

sleep 2

pw-link "main:out_0" "909:in_0"
pw-link "909:out_0" "alsa_output.platform-fe00b840.mailbox.stereo-fallback:playback_FL"
pw-link "909:out_1" "alsa_output.platform-fe00b840.mailbox.stereo-fallback:playback_FR"

cat <<EOF
Kick suite started.

Ports wired:
  main:out_0 -> 909:in_0
  909:out_0 -> playback_FL
  909:out_1 -> playback_FR

Logs:
  ${LOG_DIR}/main.log
  ${LOG_DIR}/909.log
  ${LOG_DIR}/carla-patchbay.log
EOF
