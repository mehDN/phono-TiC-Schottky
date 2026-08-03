#!/usr/bin/env bash
# Generate finite-displacement POSCAR-* for nodef, cVac, 2G.
# Requires: phonopy on PATH (unless all structures already have displacements).
# Skip a structure when phonopy_disp.yaml + POSCAR-* exist unless FORCE_DISP=1.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export PATH="${HOME}/.local/bin:${PATH}"
AMP="${AMP:-0.01}"
STRUCTURES=(nodef cVac 2G)
FORCE_DISP="${FORCE_DISP:-0}"

struct_displacements_done() {
  local dir="$1" n
  [[ -f "$dir/phonopy_disp.yaml" ]] || return 1
  n=$(find "$dir" -maxdepth 1 -type f -name 'POSCAR-[0-9]*' 2>/dev/null | wc -l)
  [[ "$n" -ge 1 ]]
}

need_phonopy=0
for s in "${STRUCTURES[@]}"; do
  if [[ "$FORCE_DISP" == "1" ]] || ! struct_displacements_done "$ROOT/$s"; then
    need_phonopy=1
    break
  fi
done

PHONOPY="${PHONOPY_BIN:-phonopy}"
if [[ "$need_phonopy" -eq 1 ]]; then
  if ! command -v ${PHONOPY%% *} >/dev/null 2>&1 && [[ "$PHONOPY" != python* ]]; then
    if python3 -c "import phonopy" >/dev/null 2>&1; then
      PHONOPY="python3 -m phonopy"
    else
      echo "ERROR: phonopy not found. Try: python3 -m pip install --user phonopy" >&2
      echo "       and ensure ~/.local/bin is on PATH." >&2
      exit 1
    fi
  fi
fi

for s in "${STRUCTURES[@]}"; do
  cd "$ROOT/$s"
  if [[ ! -f POSCAR ]]; then
    echo "ERROR: $s/POSCAR missing" >&2
    exit 1
  fi

  if [[ "$FORCE_DISP" != "1" ]] && struct_displacements_done "$ROOT/$s"; then
    n=$(find . -maxdepth 1 -type f -name 'POSCAR-[0-9]*' 2>/dev/null | wc -l)
    echo "======== $s : skip (already have phonopy_disp.yaml + $n POSCAR-*) ========"
    cd "$ROOT"
    continue
  fi

  echo "======== $s : create displacements (amplitude=${AMP} A) ========"
  # Remove old displacement sets if re-running
  rm -f POSCAR-[0-9]* SPOSCAR phonopy_disp.yaml
  # shellcheck disable=SC2086
  $PHONOPY -d --dim="1 1 1" --amplitude="$AMP" -c POSCAR
  n=$(ls POSCAR-[0-9]* 2>/dev/null | wc -l)
  echo "  -> $n displaced supercells written in $s/"
  cd "$ROOT"
done

echo "Done. Next: bash scripts/02_prepare_vasp_jobs.sh"
