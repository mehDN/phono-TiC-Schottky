#!/usr/bin/env bash
# Demo: recompute Schottky vib term from existing phono_222 thermal yaml files
# (illustrates the correct free_energy formula; does not re-run VASP).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/../phono_222"
OUT="$ROOT/results"

mkdir -p "$OUT"

# Map phono_222 names → thermal yaml
# nodef, cVac, 2g
if [[ ! -f "$SRC/nodef/thermal_properties.yaml" ]]; then
  echo "phono_222 thermal_properties.yaml not found — skip demo" >&2
  exit 1
fi

# Example static TOTEN from phono_222 OUTCARs (recompute for production!)
python3 "$ROOT/scripts/schottky_from_thermal.py" \
  --nodef "$SRC/nodef/thermal_properties.yaml" \
  --cvac  "$SRC/cVac/thermal_properties.yaml" \
  --twog  "$SRC/2g/thermal_properties.yaml" \
  --edft-nodef -588.59548361 \
  --edft-cvac  -579.41447515 \
  --edft-2g    -574.37299057 \
  --out "$OUT/schottky_demo_from_phono222.dat"

echo "---- head of result ----"
head -15 "$OUT/schottky_demo_from_phono222.dat"
