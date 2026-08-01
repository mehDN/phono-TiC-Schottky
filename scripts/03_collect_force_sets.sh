#!/usr/bin/env bash
# Collect vasprun.xml from disp_* → FORCE_SETS → FORCE_CONSTANTS.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export PATH="${HOME}/.local/bin:${PATH}"
PHONOPY="${PHONOPY_BIN:-phonopy}"
if ! command -v ${PHONOPY%% *} >/dev/null 2>&1 && [[ "$PHONOPY" != python3* ]]; then
  if python3 -c "import phonopy" >/dev/null 2>&1; then
    PHONOPY="python3 -m phonopy"
  else
    echo "ERROR: phonopy not found. Try: python3 -m pip install --user phonopy" >&2
    exit 1
  fi
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
  $PHONOPY -f "${runs[@]}"

  # Write full force constants for later mesh/band
  # shellcheck disable=SC2086
  $PHONOPY --writefc --full-fc -c POSCAR --dim="1 1 1"

  if [[ ! -f FORCE_SETS ]]; then
    echo "ERROR: FORCE_SETS not created in $s" >&2
    exit 1
  fi
  echo "  -> FORCE_SETS and FORCE_CONSTANTS written"
  cd "$ROOT"
done

echo "Done. Next: bash scripts/04_thermal_properties.sh"
