#!/usr/bin/env bash
# Compute thermal_properties.yaml (ZPE + F_vib(T)) for each structure.
# Uses phonopy Python API (v4-friendly) via run_phonopy_thermal.py.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export PATH="${HOME}/.local/bin:${PATH}"

MESH="${MESH:-32 32 32}"
TMAX="${TMAX:-2000}"
TSTEP="${TSTEP:-10}"
STRUCTURES=(nodef cVac 2G)

for s in "${STRUCTURES[@]}"; do
  if [[ ! -f "$ROOT/$s/FORCE_SETS" && ! -f "$ROOT/$s/FORCE_CONSTANTS" ]]; then
    echo "ERROR: need FORCE_SETS or FORCE_CONSTANTS in $s" >&2
    exit 1
  fi
done

# Prefer interpreter that can import phonopy (often python3.13 for pip --user)
PY=python3
if python3.13 -c "import phonopy" >/dev/null 2>&1; then
  PY=python3.13
elif ! python3 -c "import phonopy" >/dev/null 2>&1; then
  echo "ERROR: no Python with phonopy module. Try: python3 -m pip install --user phonopy" >&2
  exit 1
fi

echo "======== thermal properties mesh=($MESH) Tmax=$TMAX dT=$TSTEP ($PY) ========"
# shellcheck disable=SC2086
$PY "$ROOT/scripts/run_phonopy_thermal.py" \
  --mesh $MESH --tmin 0 --tmax "$TMAX" --tstep "$TSTEP" \
  "$ROOT/nodef" "$ROOT/cVac" "$ROOT/2G"

for s in "${STRUCTURES[@]}"; do
  zpe=$(awk '/zero_point_energy/ {print $2; exit}' "$ROOT/$s/thermal_properties.yaml")
  natom=$(awk '/^natom:/ {print $2; exit}' "$ROOT/$s/thermal_properties.yaml")
  echo "  $s: natom=$natom  ZPE=$zpe kJ/mol (supercell)"
done

echo "Done. Next:
  bash scripts/compute_schottky_thermal.sh --schottky-only
  or: python3 scripts/schottky_from_thermal.py --help"
