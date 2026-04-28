#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MATLAB_DIR="${ROOT_DIR}/matlab"
TARGET="${1:-rps_conv2_2}"

if [[ ! -d "${MATLAB_DIR}" ]]; then
  echo "ERROR: MATLAB repo not found at ${MATLAB_DIR}" >&2
  exit 2
fi

if ! command -v matlab >/dev/null 2>&1; then
  echo "ERROR: matlab command not found in PATH" >&2
  exit 3
fi

if [[ "${TARGET}" == *.m ]]; then
  TARGET_SCRIPT="${TARGET}"
else
  TARGET_SCRIPT="${TARGET}.m"
fi

if [[ ! -f "${MATLAB_DIR}/${TARGET_SCRIPT}" ]]; then
  echo "ERROR: target script not found: ${MATLAB_DIR}/${TARGET_SCRIPT}" >&2
  exit 4
fi

LOG_DIR="${ROOT_DIR}/matlab/logs"
mkdir -p "${LOG_DIR}"
TS="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="${LOG_DIR}/${TARGET%.*}_${TS}.log"

MATLAB_EXPR="cd('${MATLAB_DIR}'); set(0,'DefaultFigureVisible','off'); run('${TARGET_SCRIPT}');"

echo "[run_golden] target=${TARGET_SCRIPT}"
echo "[run_golden] matlab_dir=${MATLAB_DIR}"
echo "[run_golden] log=${LOG_FILE}"

set +e
matlab -batch "${MATLAB_EXPR}" 2>&1 | tee "${LOG_FILE}"
EC=${PIPESTATUS[0]}
set -e

echo "[run_golden] exit_code=${EC}"
echo "[run_golden] log=${LOG_FILE}"
exit "${EC}"
