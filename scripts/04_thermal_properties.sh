#!/usr/bin/env bash
# Compute thermal_properties.yaml (ZPE + F_vib(T)) for each structure.
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

MESH="${MESH:-32 32 32}"
TMAX="${TMAX:-2000}"
TSTEP="${TSTEP:-10}"
STRUCTURES=(nodef cVac 2G)

for s in "${STRUCTURES[@]}"; do
  echo "======== thermal properties: $s  mesh=($MESH) ========"
  cd "$ROOT/$s"

  if [[ ! -f FORCE_SETS && ! -f FORCE_CONSTANTS ]]; then
    echo "ERROR: need FORCE_SETS or FORCE_CONSTANTS in $s" >&2
    exit 1
  fi

  # Use FORCE_CONSTANTS if present (faster re-runs)
  if [[ -f FORCE_CONSTANTS ]]; then
    cp "$ROOT/templates/mesh.conf" mesh.conf
    # mesh.conf already has FORCE_CONSTANTS = READ
    # shellcheck disable=SC2086
    $PHONOPY -c POSCAR mesh.conf -t --tmax="$TMAX" --tstep="$TSTEP"
  else
    # shellcheck disable=SC2086
    $PHONOPY -c POSCAR -t --dim="1 1 1" --mesh="$MESH" \
      --tmax="$TMAX" --tstep="$TSTEP"
  fi

  if [[ ! -f thermal_properties.yaml ]]; then
    echo "ERROR: thermal_properties.yaml not written in $s" >&2
    exit 1
  fi

  # Optional band structure (does not fail the pipeline)
  if [[ -f FORCE_CONSTANTS ]]; then
    # shellcheck disable=SC2086
    $PHONOPY -c POSCAR -p -s "$ROOT/templates/band.conf" || true
  fi

  zpe=$(awk '/zero_point_energy/ {print $2; exit}' thermal_properties.yaml)
  natom=$(awk '/^natom:/ {print $2; exit}' thermal_properties.yaml)
  echo "  -> natom=$natom  ZPE=$zpe kJ/mol (supercell)"
  cd "$ROOT"
done

echo "Done. Next: python3 scripts/schottky_from_thermal.py --help"
