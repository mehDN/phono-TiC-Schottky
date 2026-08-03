#!/usr/bin/env bash
# =============================================================================
# compute_schottky_thermal.sh
#
# End-to-end: phonopy thermal_properties.yaml (nodef, cVac, 2G)
#            → Schottky free energy, entropy, and heat capacity vs T
#            → results/schottky_{free_energy,entropy,heat_capacity}.dat
#
# Formula (N=32 sites/sublattice, 2×2×2 TiC):
#   X_Schottky(T) = X_2G(T) + X_cVac(T) - (63/32) * X_nodef(T)
#   F_f(T)        = E_DFT_Schottky + dF_vib(T)   (if static energies given)
#
# Usage:
#   bash scripts/compute_schottky_thermal.sh              # full pipeline
#   bash scripts/compute_schottky_thermal.sh --thermal-only
#   bash scripts/compute_schottky_thermal.sh --schottky-only
#   bash scripts/compute_schottky_thermal.sh --skip-fc     # skip FORCE_SETS rebuild
#
# Environment (optional):
#   PHONOPY_BIN, PHONOPY_INIT_BIN
#   MESH="32 32 32"  TMAX=2000  TSTEP=10
#   EDFT_NODEF  EDFT_CVAC  EDFT_2G   # static TOTEN (eV)
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SCRIPTS="$ROOT/scripts"
RESULTS="$ROOT/results"
STRUCTURES=(nodef cVac 2G)

export PATH="${HOME}/.local/bin:${PATH}"

MESH="${MESH:-32 32 32}"
TMAX="${TMAX:-2000}"
TSTEP="${TSTEP:-10}"
# Keep v3 behaviour: input cell is the primitive/supercell as given (already 2x2x2)
PA="${PA:-P}"

DO_FORCE=1
DO_THERMAL=1
DO_SCHOTTKY=1
FORCE_REBUILD=0

usage() {
  sed -n '2,30p' "$0" | sed 's/^# \?//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage ;;
    --thermal-only) DO_FORCE=0; DO_THERMAL=1; DO_SCHOTTKY=1; shift ;;
    --schottky-only) DO_FORCE=0; DO_THERMAL=0; DO_SCHOTTKY=1; shift ;;
    --skip-fc) DO_FORCE=0; shift ;;
    --force-rebuild) FORCE_REBUILD=1; shift ;;
    *)
      echo "ERROR: unknown option: $1 (try --help)" >&2
      exit 1
      ;;
  esac
done

log() { echo "[$(date '+%H:%M:%S')] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# ---------- resolve phonopy (v4: phonopy + phonopy-init) ----------
resolve_phonopy() {
  if [[ -n "${PHONOPY_BIN:-}" ]]; then
    :
  elif command -v phonopy >/dev/null 2>&1; then
    PHONOPY_BIN="$(command -v phonopy)"
  elif [[ -x "${HOME}/.local/bin/phonopy" ]]; then
    PHONOPY_BIN="${HOME}/.local/bin/phonopy"
  elif python3.13 -c "import phonopy" >/dev/null 2>&1; then
    PHONOPY_BIN="python3.13 -m phonopy"
  elif python3 -c "import phonopy" >/dev/null 2>&1; then
    PHONOPY_BIN="python3 -m phonopy"
  else
    return 1
  fi
  export PHONOPY_BIN

  if [[ -n "${PHONOPY_INIT_BIN:-}" ]]; then
    :
  elif command -v phonopy-init >/dev/null 2>&1; then
    PHONOPY_INIT_BIN="$(command -v phonopy-init)"
  elif [[ -x "${HOME}/.local/bin/phonopy-init" ]]; then
    PHONOPY_INIT_BIN="${HOME}/.local/bin/phonopy-init"
  else
    # phonopy v3 fallback: same binary for -f
    PHONOPY_INIT_BIN="$PHONOPY_BIN"
  fi
  export PHONOPY_INIT_BIN
  return 0
}

if ! resolve_phonopy; then
  die "phonopy not found. Install with:  python3 -m pip install --user 'phonopy>=2.20'
  or ensure \$HOME/.local/bin is on PATH."
fi
log "phonopy:      $PHONOPY_BIN"
log "phonopy-init: $PHONOPY_INIT_BIN"
# shellcheck disable=SC2086
$PHONOPY_BIN -h >/dev/null 2>&1 || die "cannot run phonopy"

mkdir -p "$RESULTS"

# ---------- optional static DFT energies ----------
# Prefer env vars; else try results/static_energies.example.dat or results/static_energies.dat
read_static_energies() {
  local f
  for f in "$RESULTS/static_energies.dat" "$RESULTS/static_energies.example.dat"; do
    [[ -f "$f" ]] || continue
    # lines: structure  natom  TOTEN
    while read -r name _nat en; do
      [[ "$name" =~ ^# ]] && continue
      [[ -z "${name:-}" ]] && continue
      case "$name" in
        nodef) EDFT_NODEF="${EDFT_NODEF:-$en}" ;;
        cVac)  EDFT_CVAC="${EDFT_CVAC:-$en}" ;;
        2G)    EDFT_2G="${EDFT_2G:-$en}" ;;
      esac
    done < <(awk 'NF>=3 && $1 !~ /^#/ {print $1, $2, $3}' "$f")
    break
  done
}
read_static_energies

# =============================================================================
# Step A — FORCE_SETS (+ optional FORCE_CONSTANTS)
# =============================================================================
if [[ "$DO_FORCE" -eq 1 ]]; then
  for s in "${STRUCTURES[@]}"; do
    cd "$ROOT/$s"
    if [[ -f FORCE_SETS && "$FORCE_REBUILD" -eq 0 ]]; then
      log "$s: FORCE_SETS already present — skip collection"
      continue
    fi
    [[ -f phonopy_disp.yaml ]] || die "$s: missing phonopy_disp.yaml (run displacement step first)"
    shopt -s nullglob
    runs=(disp_*/vasprun.xml)
    shopt -u nullglob
    (( ${#runs[@]} > 0 )) || die "$s: no disp_*/vasprun.xml — finish VASP force jobs first"

    mapfile -t runs < <(printf '%s\n' disp_*/vasprun.xml | sort -t_ -k2 -n)
    log "$s: collecting FORCE_SETS from ${#runs[@]} vasprun.xml (phonopy-init -f)"
    # shellcheck disable=SC2086
    $PHONOPY_INIT_BIN -f "${runs[@]}"
    [[ -f FORCE_SETS ]] || die "$s: FORCE_SETS not created"
    log "$s: FORCE_SETS written"
  done
  cd "$ROOT"
fi

# =============================================================================
# Step B — thermal properties → thermal_properties.yaml  (Python API / phonopy v4)
# =============================================================================
if [[ "$DO_THERMAL" -eq 1 ]]; then
  for s in "${STRUCTURES[@]}"; do
    [[ -f "$ROOT/$s/FORCE_SETS" || -f "$ROOT/$s/FORCE_CONSTANTS" ]] \
      || die "$s: need FORCE_SETS or FORCE_CONSTANTS (run without --skip-fc)"
  done

  log "thermal properties  mesh=($MESH)  Tmax=$TMAX  dT=$TSTEP  (run_phonopy_thermal.py)"
  # Prefer the same interpreter that can import phonopy
  PY=python3
  if python3.13 -c "import phonopy" >/dev/null 2>&1; then
    PY=python3.13
  elif ! python3 -c "import phonopy" >/dev/null 2>&1; then
    die "no Python with phonopy module (tried python3.13 and python3)"
  fi

  # shellcheck disable=SC2086
  $PY "$SCRIPTS/run_phonopy_thermal.py" \
    --mesh $MESH \
    --tmin 0 \
    --tmax "$TMAX" \
    --tstep "$TSTEP" \
    --copy-to "$RESULTS" \
    "$ROOT/nodef" "$ROOT/cVac" "$ROOT/2G"

  for s in "${STRUCTURES[@]}"; do
    [[ -f "$ROOT/$s/thermal_properties.yaml" ]] \
      || die "$s: thermal_properties.yaml was not written"
    zpe=$(awk '/zero_point_energy/ {print $2; exit}' "$ROOT/$s/thermal_properties.yaml")
    natom=$(awk '/^natom:/ {print $2; exit}' "$ROOT/$s/thermal_properties.yaml")
    log "$s: natom=$natom  ZPE=$zpe kJ/mol → results/thermal_properties_${s}.yaml"
  done
fi

# =============================================================================
# Step C — Schottky F, S, Cv vs T
# =============================================================================
if [[ "$DO_SCHOTTKY" -eq 1 ]]; then
  for s in "${STRUCTURES[@]}"; do
    [[ -f "$ROOT/$s/thermal_properties.yaml" ]] \
      || die "missing $s/thermal_properties.yaml — run thermal step first"
  done

  log "Schottky free energy, entropy, Cv → $RESULTS/"
  py_args=(
    --nodef "$ROOT/nodef/thermal_properties.yaml"
    --cvac  "$ROOT/cVac/thermal_properties.yaml"
    --twog  "$ROOT/2G/thermal_properties.yaml"
    --out-dir "$RESULTS"
    --out "$RESULTS/schottky.dat"
    --prefix schottky
  )
  if [[ -n "${EDFT_NODEF:-}" && -n "${EDFT_CVAC:-}" && -n "${EDFT_2G:-}" ]]; then
    log "Using static DFT: nodef=$EDFT_NODEF  cVac=$EDFT_CVAC  2G=$EDFT_2G eV"
    py_args+=(--edft-nodef "$EDFT_NODEF" --edft-cvac "$EDFT_CVAC" --edft-2g "$EDFT_2G")
  else
    log "No full static DFT set — vibrational terms only (set EDFT_* or results/static_energies.dat)"
  fi

  python3 "$SCRIPTS/schottky_from_thermal.py" "${py_args[@]}"

  # PDFs vs temperature
  plot_py=python3
  if python3.13 -c "import matplotlib" >/dev/null 2>&1; then
    plot_py=python3.13
  elif ! python3 -c "import matplotlib" >/dev/null 2>&1; then
    plot_py=""
    echo "WARNING: matplotlib not found — skip PDF plots" >&2
  fi
  if [[ -n "$plot_py" ]]; then
    log "Plotting Schottky F, S, Cv vs T → PDF"
    $plot_py "$SCRIPTS/plot_schottky.py" --results-dir "$RESULTS" --prefix schottky
  fi

  echo
  log "Done. Results:"
  ls -la \
    "$RESULTS/schottky_free_energy.dat" \
    "$RESULTS/schottky_entropy.dat" \
    "$RESULTS/schottky_heat_capacity.dat" \
    "$RESULTS/schottky.dat" \
    "$RESULTS"/schottky_*.pdf \
    "$RESULTS"/thermal_properties_*.yaml 2>/dev/null || true
  echo
  echo "---- free energy (head) ----"
  head -8 "$RESULTS/schottky_free_energy.dat" || true
  echo "---- entropy (head) ----"
  head -8 "$RESULTS/schottky_entropy.dat" || true
  echo "---- heat capacity (head) ----"
  head -8 "$RESULTS/schottky_heat_capacity.dat" || true
fi
