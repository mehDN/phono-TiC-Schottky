#!/usr/bin/env bash
# Collect vasprun.xml from disp_* → FORCE_SETS → FORCE_CONSTANTS.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export PATH="${HOME}/.local/bin:${PATH}"
# phonopy v4: force-set collection lives in phonopy-init; phonon calc in phonopy
PHONOPY="${PHONOPY_BIN:-phonopy}"
PHONOPY_INIT="${PHONOPY_INIT_BIN:-phonopy-init}"
if ! command -v ${PHONOPY%% *} >/dev/null 2>&1 && [[ "$PHONOPY" != python3* ]]; then
  if python3.13 -c "import phonopy" >/dev/null 2>&1; then
    PHONOPY="python3.13 -m phonopy"
  elif python3 -c "import phonopy" >/dev/null 2>&1; then
    PHONOPY="python3 -m phonopy"
  else
    echo "ERROR: phonopy not found. Try: python3 -m pip install --user phonopy" >&2
    exit 1
  fi
fi
if ! command -v ${PHONOPY_INIT%% *} >/dev/null 2>&1; then
  # v3 fallback: same binary handles -f
  PHONOPY_INIT="$PHONOPY"
fi

STRUCTURES=(nodef cVac 2G)

for s in "${STRUCTURES[@]}"; do
  echo "======== FORCE_SETS: $s ========"
  cd "$ROOT/$s"

  shopt -s nullglob
  runs=(disp_*/vasprun.xml)
  shopt -u nullglob
  if (( ${#runs[@]} == 0 )); then
    echo "ERROR: no disp_*/vasprun.xml in $s" >&2
    exit 1
  fi

  # Ensure phonopy_disp.yaml exists (created in step 01)
  if [[ ! -f phonopy_disp.yaml ]]; then
    echo "ERROR: phonopy_disp.yaml missing in $s" >&2
    exit 1
  fi

  # Sort numerically by directory index
  mapfile -t runs < <(printf '%s\n' disp_*/vasprun.xml | sort -t_ -k2 -n)

  echo "  using ${#runs[@]} vasprun.xml files"
  # shellcheck disable=SC2086
  $PHONOPY_INIT -f "${runs[@]}"

  # Write full force constants for later mesh/band (phonopy calculation CLI)
  # shellcheck disable=SC2086
  if [[ -f phonopy_disp.yaml ]]; then
    $PHONOPY --writefc --full-fc --dim="1 1 1" --pa P phonopy_disp.yaml || true
  else
    $PHONOPY --writefc --full-fc --dim="1 1 1" --pa P || true
  fi

  if [[ ! -f FORCE_SETS ]]; then
    echo "ERROR: FORCE_SETS not created in $s" >&2
    exit 1
  fi
  echo "  -> FORCE_SETS written (FORCE_CONSTANTS if writefc succeeded)"
  cd "$ROOT"
done

echo "Done. Next: bash scripts/04_thermal_properties.sh
  or: bash scripts/compute_schottky_thermal.sh"
