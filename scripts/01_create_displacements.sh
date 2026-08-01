#!/usr/bin/env bash
# Generate finite-displacement POSCAR-* for nodef, cVac, 2G.
# Requires: phonopy on PATH.
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
    echo "       and ensure ~/.local/bin is on PATH." >&2
    exit 1
  fi
fi

AMP="${AMP:-0.01}"
STRUCTURES=(nodef cVac 2G)

for s in "${STRUCTURES[@]}"; do
  echo "======== $s : create displacements (amplitude=${AMP} A) ========"
  cd "$ROOT/$s"
  if [[ ! -f POSCAR ]]; then
    echo "ERROR: $s/POSCAR missing" >&2
    exit 1
  fi
  # Remove old displacement sets if re-running
  rm -f POSCAR-[0-9]* SPOSCAR phonopy_disp.yaml
  # shellcheck disable=SC2086
  $PHONOPY -d --dim="1 1 1" --amplitude="$AMP" -c POSCAR
  n=$(ls POSCAR-[0-9]* 2>/dev/null | wc -l)
  echo "  -> $n displaced supercells written in $s/"
  cd "$ROOT"
done

echo "Done. Next: bash scripts/02_prepare_vasp_jobs.sh"
