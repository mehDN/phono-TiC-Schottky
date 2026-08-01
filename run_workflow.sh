#!/usr/bin/env bash
# =============================================================================
# run_workflow.sh  —  full Schottky / phonopy pipeline for TiC (nodef, cVac, 2G)
#
# Location: phono/run_workflow.sh  (outside scripts/)
# Usage:
#   ./run_workflow.sh                  # all steps (prompts before VASP submit)
#   ./run_workflow.sh --auto-submit    # submit VASP jobs without asking
#   ./run_workflow.sh --from 3         # resume from step 3
#   ./run_workflow.sh --only 4         # run only step 4
#   ./run_workflow.sh --demo           # Schottky from existing phono_222 data
#   ./run_workflow.sh --help
#
# Steps:
#   0  check prerequisites
#   1  static DFT energy jobs          (scripts/05_static_energies.sh)
#   2  create finite displacements     (scripts/01_create_displacements.sh)
#   3  prepare + optionally submit VASP force jobs
#   4  collect FORCE_SETS / FC         (scripts/03_collect_force_sets.sh)
#   5  thermal properties / ZPE        (scripts/04_thermal_properties.sh)
#   6  Schottky free energy table      (scripts/schottky_from_thermal.py)
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
SCRIPTS="$ROOT/scripts"
RESULTS="$ROOT/results"
mkdir -p "$RESULTS"

# Ensure user-local installs (pip --user) are visible, e.g. ~/.local/bin/phonopy
export PATH="${HOME}/.local/bin:${PATH}"

# Host-aware defaults (Metis: MAX_JOBS=7 × NPROC=8 = 56 cores; wc_114 pattern)
# shellcheck source=scripts/cluster_env.sh
source "$SCRIPTS/cluster_env.sh"

# ---------- defaults / environment (override on the command line) ----------
AUTO_SUBMIT=0
FROM_STEP=0
ONLY_STEP=""
DEMO=0
SKIP_STATIC=0
AMP="${AMP:-0.01}"
MESH="${MESH:-32 32 32}"
TMAX="${TMAX:-2000}"
TSTEP="${TSTEP:-10}"
# Optional static TOTEN (eV). If unset, step 6 tries static/OUTCAR or example file.
EDFT_NODEF="${EDFT_NODEF:-}"
EDFT_CVAC="${EDFT_CVAC:-}"
EDFT_2G="${EDFT_2G:-}"

STRUCTURES=(nodef cVac 2G)

usage() {
  cat <<EOF
run_workflow.sh — full Schottky / phonopy pipeline (nodef, cVac, 2G)

Usage:
  ./run_workflow.sh                  # all steps (prompts before VASP submit)
  ./run_workflow.sh --auto-submit    # submit VASP jobs without asking
  ./run_workflow.sh --from 3         # resume from step 3
  ./run_workflow.sh --only 4         # run only step 4
  ./run_workflow.sh --skip-static    # skip step 1 static DFT staging
  ./run_workflow.sh --demo           # Schottky from existing phono_222 data
  ./run_workflow.sh --help

Steps:
  0  check prerequisites
  1  static DFT energy jobs          (scripts/05_static_energies.sh)
  2  create finite displacements     (scripts/01_create_displacements.sh)
  3  prepare + optionally submit VASP force jobs
  4  collect FORCE_SETS / FC         (scripts/03_collect_force_sets.sh)
  5  thermal properties / ZPE        (scripts/04_thermal_properties.sh)
  6  Schottky free energy table      (scripts/schottky_from_thermal.py)

Environment overrides:
  AMP=0.01  MESH="32 32 32"  TMAX=2000  TSTEP=10
  RUN_MODE=metis|slurm|local       (auto-detected from hostname)
  NPROC=8  MAX_JOBS=7              (Metis only; 7×8=56 cores — do NOT use Leto)
  ACCOUNT  NODES  NTASKS  WALLTIME  VASP_CMD   (SLURM)
  EDFT_NODEF  EDFT_CVAC  EDFT_2G     (eV; skip OUTCAR scrape in step 6)

Current host: $(hostname -s 2>/dev/null || hostname)  RUN_MODE=${RUN_MODE}
  TARGET: metis.mse.kth.se (NOT leto)
  Metis pool: MAX_JOBS=${MAX_JOBS} × NPROC=${NPROC} = ${TOTAL_CORES} cores

Examples (on Metis):
  ssh metis && cd /slask/mehdin/dynamics/phono
  AMP=0.015 ./run_workflow.sh --from 2
  ./run_workflow.sh --auto-submit                          # Metis local parallel ≤56 cores
  MAX_JOBS=14 NPROC=4 ./run_workflow.sh --auto-submit
  EDFT_NODEF=-588.59 EDFT_CVAC=-579.41 EDFT_2G=-574.37 ./run_workflow.sh --only 6
  ./run_workflow.sh --demo
EOF
}

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

should_run() {
  local step="$1"
  if [[ -n "$ONLY_STEP" ]]; then
    [[ "$step" == "$ONLY_STEP" ]]
  else
    [[ "$step" -ge "$FROM_STEP" ]]
  fi
}

# ---------- parse args ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --auto-submit) AUTO_SUBMIT=1; shift ;;
    --from)
      FROM_STEP="${2:?--from needs a step number 0-6}"
      shift 2
      ;;
    --only)
      ONLY_STEP="${2:?--only needs a step number 0-6}"
      shift 2
      ;;
    --demo) DEMO=1; shift ;;
    --skip-static) SKIP_STATIC=1; shift ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
done

# ---------- demo short-circuit ----------
if [[ "$DEMO" -eq 1 ]]; then
  log "Demo: Schottky from phono_222 thermal_properties.yaml"
  bash "$SCRIPTS/run_demo_from_phono222.sh"
  exit 0
fi

# =============================================================================
# Step 0 — prerequisites
# =============================================================================
if should_run 0; then
  log "Step 0: prerequisites"
  for s in "${STRUCTURES[@]}"; do
    [[ -f "$ROOT/$s/POSCAR" ]] || die "missing $s/POSCAR"
    [[ -f "$ROOT/$s/POTCAR" ]] || die "missing $s/POTCAR"
  done
  # Resolve phonopy: PATH, ~/.local/bin, or python -m phonopy
  resolve_phonopy() {
    if command -v phonopy >/dev/null 2>&1; then
      command -v phonopy
      return 0
    fi
    if [[ -x "${HOME}/.local/bin/phonopy" ]]; then
      export PATH="${HOME}/.local/bin:${PATH}"
      echo "${HOME}/.local/bin/phonopy"
      return 0
    fi
    if python3 -c "import phonopy" >/dev/null 2>&1; then
      # wrapper used when only the module is installed
      PHONOPY_CMD="python3 -m phonopy"
      echo "python3 -m phonopy"
      return 0
    fi
    return 1
  }

  if PHONOPY_BIN="$(resolve_phonopy)"; then
    export PHONOPY_BIN
    echo "  phonopy: $PHONOPY_BIN"
    # shellcheck disable=SC2086
    $PHONOPY_BIN --version 2>/dev/null || true
  else
    if should_run 2 || should_run 4 || should_run 5; then
      die "phonopy not found. Install with:  python3 -m pip install --user phonopy
  or add the phonopy binary directory to PATH (often ~/.local/bin)."
    else
      warn "phonopy not found (OK if you only stage VASP / run step 6 later)"
    fi
  fi
  cluster_summary
  if is_leto_host; then
    warn "You are on Leto — this phono VASP pipeline is for Metis only."
    warn "  ssh metis && cd $ROOT && ./run_workflow.sh ..."
  fi
  if [[ "$RUN_MODE" == "metis" || "$RUN_MODE" == "local" ]]; then
    if is_metis_host; then
      echo "  Host check: Metis OK"
    else
      warn "Not on Metis (hostname=$(cluster_hostname)); local VASP launch will refuse Leto / may prompt"
    fi
    [[ -e "$VASP_BIN" ]] || warn "VASP_BIN not found: $VASP_BIN"
    [[ -f "$ONEAPI_SETVARS" ]] || warn "oneAPI setvars missing: $ONEAPI_SETVARS (VASP may fail to load MKL)"
    command -v mpirun >/dev/null 2>&1 || warn "mpirun not on PATH until oneAPI is sourced (r.sh sources it)"
  elif [[ "$RUN_MODE" == "wrong_host" ]]; then
    warn "RUN_MODE=wrong_host (Leto). Switch to Metis before submitting VASP."
  else
    command -v sbatch >/dev/null 2>&1 || warn "sbatch not found — jobs will not be submitted automatically"
  fi
  echo "  POSCARs OK: nodef=64, cVac=63, 2G=63 (expected)"
fi

# =============================================================================
# Step 1 — stage static DFT energy calculations
# =============================================================================
if should_run 1 && [[ "$SKIP_STATIC" -eq 0 ]]; then
  log "Step 1: stage static total-energy jobs (nodef/cVac/2G/static)"
  bash "$SCRIPTS/05_static_energies.sh"

  do_static_submit=0
  if [[ "$AUTO_SUBMIT" -eq 1 ]]; then
    do_static_submit=1
  else
    read -r -p "Run static VASP jobs now? [y/N] " ans || true
    [[ "${ans:-}" =~ ^[Yy]$ ]] && do_static_submit=1
  fi

  if [[ "$do_static_submit" -eq 1 ]]; then
    if [[ "$RUN_MODE" == "metis" || "$RUN_MODE" == "local" ]]; then
      log "Running static jobs locally (MAX_JOBS=${MAX_JOBS} × NPROC=${NPROC} = ${TOTAL_CORES} cores)"
      bash "$SCRIPTS/run_local_parallel.sh" --static "${STRUCTURES[@]}"
      log "Static jobs finished (or failed — check */static/o.dat)."
    elif command -v sbatch >/dev/null 2>&1; then
      for s in "${STRUCTURES[@]}"; do
        ( cd "$ROOT/$s/static" && sbatch r.sh )
      done
      log "Static jobs submitted. Wait for them before relying on step-6 DFT term."
    else
      warn "No runner available (no Metis mode / no sbatch). Run static r.sh manually."
    fi
  else
    if [[ "$RUN_MODE" == "metis" || "$RUN_MODE" == "local" ]]; then
      warn "Skipped static. Later:  bash scripts/run_local_parallel.sh --static"
    else
      warn "Skipped static submit. Later:  for s in nodef cVac 2G; do (cd \$s/static && sbatch r.sh); done"
    fi
  fi
elif should_run 1 && [[ "$SKIP_STATIC" -eq 1 ]]; then
  warn "Step 1 skipped (--skip-static)"
fi

# =============================================================================
# Step 2 — finite displacements
# =============================================================================
if should_run 2; then
  log "Step 2: create phonopy displacements (AMP=${AMP} A)"
  export AMP
  bash "$SCRIPTS/01_create_displacements.sh"
fi

# =============================================================================
# Step 3 — prepare (and optionally submit) force jobs
# =============================================================================
if should_run 3; then
  log "Step 3: prepare VASP finite-displacement force jobs"
  bash "$SCRIPTS/02_prepare_vasp_jobs.sh"

  njobs=0
  for s in "${STRUCTURES[@]}"; do
    n=$(find "$ROOT/$s" -maxdepth 1 -type d -name 'disp_*' 2>/dev/null | wc -l)
    njobs=$((njobs + n))
  done
  echo "  Total displacement jobs staged: $njobs"
  cluster_summary

  do_force_submit=0
  ans=""
  if [[ "$AUTO_SUBMIT" -eq 1 ]]; then
    do_force_submit=1
  else
    if [[ "$RUN_MODE" == "metis" || "$RUN_MODE" == "local" ]]; then
      read -r -p "Run all $njobs force jobs now on Metis only (MAX_JOBS=${MAX_JOBS} × NPROC=${NPROC} = ${TOTAL_CORES} cores; not Leto)? [y/N] " ans || true
    else
      read -r -p "Submit all $njobs force jobs now? [y/N] " ans || true
    fi
    [[ "${ans:-}" =~ ^[Yy]$ ]] && do_force_submit=1
  fi

  if [[ "$do_force_submit" -eq 1 ]]; then
    if [[ "$RUN_MODE" == "metis" || "$RUN_MODE" == "local" ]]; then
      log "Running force jobs on Metis: MAX_JOBS=${MAX_JOBS} × NPROC=${NPROC} = ${TOTAL_CORES} cores"
      # Blocks until all pending finish (or non-zero on failures)
      bash "$SCRIPTS/run_local_parallel.sh" "${STRUCTURES[@]}"
    elif command -v sbatch >/dev/null 2>&1; then
      log "Submitting all force jobs via sbatch"
      for s in "${STRUCTURES[@]}"; do
        ( cd "$ROOT/$s" && ./submit_all.sh )
      done
      # Wait unless --only 3
      if [[ -z "$ONLY_STEP" || "$ONLY_STEP" != "3" ]]; then
        log "Waiting for force jobs: all disp_*/vasprun.xml must exist"
        echo "  Polling every 120 s (Ctrl-C to exit; later: ./run_workflow.sh --from 4)"
        while true; do
          missing=0
          for s in "${STRUCTURES[@]}"; do
            for d in "$ROOT/$s"/disp_*; do
              [[ -d "$d" ]] || continue
              [[ -f "$d/vasprun.xml" ]] || missing=$((missing + 1))
            done
          done
          if [[ "$missing" -eq 0 ]]; then
            echo "  All vasprun.xml present."
            break
          fi
          echo "  still missing $missing vasprun.xml … $(date +%H:%M:%S)"
          sleep 120
        done
      fi
    else
      die "No job runner: set RUN_MODE=metis or use a host with sbatch"
    fi
  else
    if [[ "$RUN_MODE" == "metis" || "$RUN_MODE" == "local" ]]; then
      warn "Not started. When ready:  bash scripts/submit_all_structures.sh"
    else
      warn "Not submitted. When ready:  for s in nodef cVac 2G; do (cd \$s && ./submit_all.sh); done"
    fi
    warn "After all VASP jobs finish, resume with:  ./run_workflow.sh --from 4"
    if [[ -z "$ONLY_STEP" && "$FROM_STEP" -le 3 ]]; then
      log "Stopping before FORCE_SETS collection (VASP not finished)."
      exit 0
    fi
  fi
fi

# =============================================================================
# Step 4 — FORCE_SETS
# =============================================================================
if should_run 4; then
  log "Step 4: collect FORCE_SETS and write FORCE_CONSTANTS"
  # Guard: refuse if any vasprun missing
  missing=0
  for s in "${STRUCTURES[@]}"; do
    for d in "$ROOT/$s"/disp_*; do
      [[ -d "$d" ]] || continue
      [[ -f "$d/vasprun.xml" ]] || { echo "  missing $d/vasprun.xml"; missing=$((missing + 1)); }
    done
  done
  [[ "$missing" -eq 0 ]] || die "$missing vasprun.xml still missing — finish VASP first"
  bash "$SCRIPTS/03_collect_force_sets.sh"
fi

# =============================================================================
# Step 5 — thermal properties
# =============================================================================
if should_run 5; then
  log "Step 5: thermal properties (mesh=$MESH  Tmax=$TMAX  dT=$TSTEP)"
  export MESH TMAX TSTEP
  bash "$SCRIPTS/04_thermal_properties.sh"
fi

# =============================================================================
# Step 6 — Schottky free energy
# =============================================================================
if should_run 6; then
  log "Step 6: Schottky formation free energy"

  for s in "${STRUCTURES[@]}"; do
    [[ -f "$ROOT/$s/thermal_properties.yaml" ]] \
      || die "missing $s/thermal_properties.yaml — run step 5 first"
  done

  scrape_toten() {
    local outcar="$1"
    if [[ -f "$outcar" ]]; then
      awk '/free  energy   TOTEN/ {e=$5} END{if(e!="") print e}' "$outcar"
    fi
  }

  if [[ -z "$EDFT_NODEF" ]]; then
    EDFT_NODEF="$(scrape_toten "$ROOT/nodef/static/OUTCAR" || true)"
  fi
  if [[ -z "$EDFT_CVAC" ]]; then
    EDFT_CVAC="$(scrape_toten "$ROOT/cVac/static/OUTCAR" || true)"
  fi
  if [[ -z "$EDFT_2G" ]]; then
    EDFT_2G="$(scrape_toten "$ROOT/2G/static/OUTCAR" || true)"
  fi

  # Fall back to example energies (documented as non-production)
  if [[ -z "$EDFT_NODEF" || -z "$EDFT_CVAC" || -z "$EDFT_2G" ]]; then
    warn "Static TOTEN incomplete — using vib-only table (pass EDFT_* or finish step 1)"
    python3 "$SCRIPTS/schottky_from_thermal.py" \
      --nodef "$ROOT/nodef/thermal_properties.yaml" \
      --cvac  "$ROOT/cVac/thermal_properties.yaml" \
      --twog  "$ROOT/2G/thermal_properties.yaml" \
      --out   "$RESULTS/schottky.dat"
  else
    echo "  EDFT nodef=$EDFT_NODEF  cVac=$EDFT_CVAC  2G=$EDFT_2G  (eV)"
    python3 "$SCRIPTS/schottky_from_thermal.py" \
      --nodef "$ROOT/nodef/thermal_properties.yaml" \
      --cvac  "$ROOT/cVac/thermal_properties.yaml" \
      --twog  "$ROOT/2G/thermal_properties.yaml" \
      --edft-nodef "$EDFT_NODEF" \
      --edft-cvac  "$EDFT_CVAC" \
      --edft-2g    "$EDFT_2G" \
      --out   "$RESULTS/schottky.dat"
  fi

  log "Finished. Results: $RESULTS/schottky.dat"
  head -12 "$RESULTS/schottky.dat" || true
fi

log "Workflow complete."
