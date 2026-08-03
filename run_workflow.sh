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
#   ./run_workflow.sh --thermal-only   # steps 5–6 (needs FORCE_SETS)
#   ./run_workflow.sh --schottky-only  # step 6 only (needs thermal yaml)
#   ./run_workflow.sh --skip-fc        # skip FORCE_SETS collection (step 4)
#   ./run_workflow.sh --force-rebuild  # re-collect FORCE_SETS even if present
#   ./run_workflow.sh --skip-bands     # skip phonon band structure in step 6
#   ./run_workflow.sh --demo           # Schottky from existing phono_222 data
#   ./run_workflow.sh --help
#
# Steps:
#   0  check prerequisites
#   1  static DFT energy jobs          (scripts/05_static_energies.sh)
#   2  create finite displacements     (scripts/01_create_displacements.sh)
#   3  prepare + optionally submit VASP force jobs
#   4  collect FORCE_SETS / FC         (scripts/03_collect_force_sets.sh)
#   5  thermal properties / ZPE        (scripts/04_thermal_properties.sh
#                                      → */thermal_properties.yaml + results/)
#   6  Schottky F, S, Cv vs T          (scripts/schottky_from_thermal.py
#                                      → results/schottky_{free_energy,entropy,
#                                         heat_capacity}.dat + schottky.dat)
#                                      + PDFs via scripts/plot_schottky.py
#                                      + phonon bands (bands.conf / bands.yaml /
#                                        bands.pdf) via run_phonopy_bands.py
#                                      + Schottky bands via schottky_bands.py
#                                        → results/bands_schottky.pdf
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
SKIP_FC=0
SKIP_PLOT=0
SKIP_BANDS=0
PLOT_ONLY=0
FORCE_REBUILD="${FORCE_REBUILD:-0}"
AMP="${AMP:-0.01}"
MESH="${MESH:-32 32 32}"
TMAX="${TMAX:-2000}"
TSTEP="${TSTEP:-10}"
BAND_POINTS="${BAND_POINTS:-51}"
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
  ./run_workflow.sh --thermal-only   # steps 5–6 only (FORCE_SETS must exist)
  ./run_workflow.sh --schottky-only  # step 6 only (thermal yaml + bands)
  ./run_workflow.sh --plot-only      # replot Schottky + bands PDFs from results/
  ./run_workflow.sh --skip-fc        # skip step 4 FORCE_SETS collection
  ./run_workflow.sh --force-rebuild  # re-run step 4 even if FORCE_SETS exist
  ./run_workflow.sh --skip-plot      # skip PDF generation after step 6
  ./run_workflow.sh --skip-bands     # skip phonon band structure in step 6
  ./run_workflow.sh --demo           # Schottky from existing phono_222 data
  ./run_workflow.sh --help

Steps:
  0  check prerequisites
  1  static DFT energy jobs          (scripts/05_static_energies.sh)
  2  create finite displacements     (scripts/01_create_displacements.sh)
     (auto-skipped if phonopy_disp.yaml + POSCAR-* already exist)
  3  prepare + optionally submit VASP force jobs
  4  collect FORCE_SETS / FC         (scripts/03_collect_force_sets.sh)
     (auto-skipped if FORCE_SETS present; use --force-rebuild to redo)
  5  thermal properties / ZPE        (scripts/04_thermal_properties.sh)
     → nodef|cVac|2G/thermal_properties.yaml
     → results/thermal_properties_{nodef,cVac,2G}.yaml
  6  Schottky free energy, entropy, Cv vs T + phonon bands
     (schottky_from_thermal.py, plot_schottky.py,
      run_phonopy_bands.py, plot_bands.py, schottky_bands.py)
     6a  results/schottky_{free_energy,entropy,heat_capacity}.dat + schottky.dat
     6b  results/schottky_{free_energy,entropy,heat_capacity,all}.pdf
     6c  nodef|cVac|2G/{bands.conf,bands.yaml,bands.pdf}
     6d  results/bands_{nodef,cVac,2G}.*  +  results/bands.pdf
     6e  results/bands_schottky.yaml + bands_schottky.pdf
         (alias: bands_schotcky.pdf)

  Formula (N=32):  X_S = X_2G + X_cVac - (63/32)*X_nodef
  for X in {E_DFT, F_vib, U_vib, S_vib, Cv, omega(q,i)}
  F_f(T) = E_DFT_Schottky + dF_vib(T)

  Docs: README.md , WORKFLOW.md

Environment overrides:
  AMP=0.01  MESH="32 32 32"  TMAX=2000  TSTEP=10
  BAND_POINTS=51                 points per band segment
  FORCE_DISP=1                   force re-run of step 2 (needs phonopy)
  FORCE_REBUILD=1                same as --force-rebuild
  PHONOPY_BIN=/path/to/phonopy   or  "python3 -m phonopy"
  PHONOPY_INIT_BIN=phonopy-init  (v4 force-set collection)
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
  ./run_workflow.sh --from 4                               # FORCE_SETS → thermal → Schottky
  ./run_workflow.sh --thermal-only                         # mesh thermal + Schottky F/S/Cv
  ./run_workflow.sh --schottky-only                        # F/S/Cv + bands + PDFs
  ./run_workflow.sh --plot-only                            # replot Schottky + bands_schottky
  ./run_workflow.sh --skip-fc --from 5                     # thermal+Schottky, keep FORCE_SETS
  ./run_workflow.sh --skip-bands                           # thermodynamics only
  MESH="48 48 48" TMAX=2000 ./run_workflow.sh --thermal-only
  BAND_POINTS=101 ./run_workflow.sh --schottky-only
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

# True if step 2 already produced displacements for every structure.
# Markers: phonopy_disp.yaml + at least one POSCAR-NNN (phonopy -d output).
displacements_complete() {
  local s n
  for s in "${STRUCTURES[@]}"; do
    [[ -f "$ROOT/$s/phonopy_disp.yaml" ]] || return 1
    n=$(find "$ROOT/$s" -maxdepth 1 -type f -name 'POSCAR-[0-9]*' 2>/dev/null | wc -l)
    [[ "$n" -ge 1 ]] || return 1
  done
  return 0
}

# True if FORCE_SETS already exist for every structure (step 4 done).
force_sets_complete() {
  local s
  for s in "${STRUCTURES[@]}"; do
    [[ -f "$ROOT/$s/FORCE_SETS" ]] || return 1
  done
  return 0
}

# True if thermal_properties.yaml exists for every structure (step 5 done).
thermal_complete() {
  local s
  for s in "${STRUCTURES[@]}"; do
    [[ -f "$ROOT/$s/thermal_properties.yaml" ]] || return 1
  done
  return 0
}

# Resolve phonopy: PATH, ~/.local/bin, or python -m phonopy.
# Sets PHONOPY_BIN and PHONOPY_INIT_BIN on success; returns 0/1.
# phonopy v4 splits CLI: phonopy-init (-f, -d) vs phonopy (thermal/mesh).
resolve_phonopy() {
  if [[ -n "${PHONOPY_BIN:-}" ]]; then
    # Honour pre-set override (path or "python3 -m phonopy")
    if [[ "$PHONOPY_BIN" == python* ]]; then
      # shellcheck disable=SC2086
      $PHONOPY_BIN -h >/dev/null 2>&1 || return 1
    elif [[ -x "$PHONOPY_BIN" ]] || command -v "$PHONOPY_BIN" >/dev/null 2>&1; then
      :
    else
      return 1
    fi
  elif command -v phonopy >/dev/null 2>&1; then
    PHONOPY_BIN="$(command -v phonopy)"
  elif [[ -x "${HOME}/.local/bin/phonopy" ]]; then
    export PATH="${HOME}/.local/bin:${PATH}"
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
    # phonopy v3: same binary handles -f / -d
    PHONOPY_INIT_BIN="$PHONOPY_BIN"
  fi
  export PHONOPY_INIT_BIN
  return 0
}

# Python interpreter that can import phonopy (for thermal API script).
resolve_phonopy_python() {
  if python3.13 -c "import phonopy" >/dev/null 2>&1; then
    PHONOPY_PYTHON=python3.13
  elif python3 -c "import phonopy" >/dev/null 2>&1; then
    PHONOPY_PYTHON=python3
  else
    return 1
  fi
  export PHONOPY_PYTHON
  return 0
}

# Load EDFT_* from results/static_energies.dat (or .example.dat) if still unset.
read_static_energies_file() {
  local f name _nat en
  for f in "$RESULTS/static_energies.dat" "$RESULTS/static_energies.example.dat"; do
    [[ -f "$f" ]] || continue
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

# phonopy is required *now* only if a phonopy-using step will actually execute
# and its artifacts are not already present. Full --auto-submit can run VASP
# first and install phonopy before steps 4–5.
phonopy_required_now() {
  if should_run 2 && ! displacements_complete; then
    return 0
  fi
  if should_run 4 && ! force_sets_complete; then
    # Need phonopy immediately if we are only doing 4, or resuming from ≥4
    if [[ "$ONLY_STEP" == "4" ]] || [[ -z "$ONLY_STEP" && "$FROM_STEP" -ge 4 ]]; then
      return 0
    fi
  fi
  if should_run 5 && ! thermal_complete; then
    if [[ "$ONLY_STEP" == "5" ]] || [[ -z "$ONLY_STEP" && "$FROM_STEP" -ge 5 ]]; then
      return 0
    fi
  fi
  return 1
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
    # Thermal / Schottky convenience options (same idea as compute_schottky_thermal.sh)
    --thermal-only)
      # FORCE_SETS → thermal yaml → Schottky F/S/Cv
      FROM_STEP=5
      SKIP_FC=1
      shift
      ;;
    --schottky-only)
      # Rebuild Schottky tables from existing thermal_properties.yaml
      FROM_STEP=6
      SKIP_FC=1
      shift
      ;;
    --skip-fc)
      SKIP_FC=1
      shift
      ;;
    --force-rebuild)
      FORCE_REBUILD=1
      SKIP_FC=0
      shift
      ;;
    --skip-plot)
      SKIP_PLOT=1
      shift
      ;;
    --skip-bands)
      SKIP_BANDS=1
      shift
      ;;
    --plot-only)
      PLOT_ONLY=1
      shift
      ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
done

# ---------- plot-only short-circuit ----------
if [[ "$PLOT_ONLY" -eq 1 ]]; then
  log "Plot Schottky F, S, Cv vs T → PDF in $RESULTS"
  plot_py=python3
  if python3.13 -c "import matplotlib" >/dev/null 2>&1; then
    plot_py=python3.13
  elif ! python3 -c "import matplotlib" >/dev/null 2>&1; then
    die "matplotlib not found (need python3.13 or python3 + matplotlib)"
  fi
  $plot_py "$SCRIPTS/plot_schottky.py" --results-dir "$RESULTS" --prefix schottky
  ls -la "$RESULTS"/schottky_*.pdf 2>/dev/null || true
  # Replot bands if bands.yaml present
  band_dirs=()
  for s in "${STRUCTURES[@]}"; do
    if [[ -f "$ROOT/$s/bands.yaml" || -f "$ROOT/$s/band.yaml" ]]; then
      band_dirs+=("$ROOT/$s")
    fi
  done
  if (( ${#band_dirs[@]} > 0 )); then
    log "Plot phonon bands → PDF in $RESULTS"
    $plot_py "$SCRIPTS/plot_bands.py" --results-dir "$RESULTS" "${band_dirs[@]}"
    ls -la "$RESULTS"/bands*.pdf 2>/dev/null || true
    if [[ -f "$ROOT/nodef/bands.yaml" && -f "$ROOT/cVac/bands.yaml" && -f "$ROOT/2G/bands.yaml" ]]; then
      log "Schottky phonon bands → bands_schottky.pdf"
      $plot_py "$SCRIPTS/schottky_bands.py" --results-dir "$RESULTS" \
        --nodef "$ROOT/nodef" --cvac "$ROOT/cVac" --twog "$ROOT/2G"
      ls -la "$RESULTS"/bands_schottky.pdf "$RESULTS"/bands_schotcky.pdf 2>/dev/null || true
    fi
  else
    warn "No bands.yaml found — skip band plots (run step 6 without --skip-bands first)"
  fi
  exit 0
fi

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
  if resolve_phonopy; then
    echo "  phonopy:      $PHONOPY_BIN"
    echo "  phonopy-init: $PHONOPY_INIT_BIN"
    # shellcheck disable=SC2086
    $PHONOPY_BIN -h >/dev/null 2>&1 && echo "  phonopy CLI OK" || true
  else
    if phonopy_required_now; then
      die "phonopy not found (needed for the step(s) you are running). Install with:
  python3 -m pip install --user phonopy
  or:  ensure ~/.local/bin is on PATH / set PHONOPY_BIN to the binary
  (often: export PHONOPY_BIN=\$HOME/.local/bin/phonopy)"
    else
      if displacements_complete; then
        echo "  phonopy: not on PATH (OK — displacements already present; skip step 2)"
      else
        warn "phonopy not found (OK for VASP-only / static; install before steps 4–5)"
      fi
      if should_run 4 || should_run 5; then
        warn "Steps 4–5 need phonopy later. Install before FORCE_SETS / thermal:
  python3 -m pip install --user phonopy"
      fi
    fi
  fi
  if resolve_phonopy_python; then
    echo "  phonopy Python: $PHONOPY_PYTHON (thermal API)"
  fi
  if displacements_complete; then
    n_disp=0
    for s in "${STRUCTURES[@]}"; do
      n_disp=$((n_disp + $(find "$ROOT/$s" -maxdepth 1 -type d -name 'disp_*' 2>/dev/null | wc -l)))
    done
    echo "  step 2 artifacts: phonopy_disp.yaml + POSCAR-* present for all structures"
    echo "  staged disp_* folders: $n_disp (step 3 prepare may already be done)"
  fi
  if force_sets_complete; then
    echo "  step 4 artifacts: FORCE_SETS present for all structures"
  fi
  if thermal_complete; then
    echo "  step 5 artifacts: thermal_properties.yaml present for all structures"
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
  if displacements_complete && [[ "${FORCE_DISP:-0}" != "1" ]]; then
    log "Step 2: skip — phonopy displacements already present"
    echo "  (found phonopy_disp.yaml + POSCAR-* in nodef, cVac, 2G)"
    echo "  Re-run with FORCE_DISP=1 to regenerate (needs phonopy)."
  else
    log "Step 2: create phonopy displacements (AMP=${AMP} A)"
    if ! resolve_phonopy; then
      die "phonopy not found. Install with:  python3 -m pip install --user phonopy
  or add the phonopy binary directory to PATH (often ~/.local/bin)."
    fi
    export AMP PHONOPY_BIN
    bash "$SCRIPTS/01_create_displacements.sh"
  fi
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
  if [[ "$SKIP_FC" -eq 1 ]]; then
    log "Step 4: skip — --skip-fc / --thermal-only / --schottky-only"
    force_sets_complete || die "FORCE_SETS missing but --skip-fc set; collect with --from 4"
  elif force_sets_complete && [[ "$FORCE_REBUILD" != "1" ]]; then
    log "Step 4: skip — FORCE_SETS already present for all structures"
    echo "  Re-run with --force-rebuild (or FORCE_REBUILD=1) to regenerate."
  else
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
    if ! resolve_phonopy; then
      die "phonopy not found (needed for FORCE_SETS). Install: python3 -m pip install --user phonopy"
    fi
    export PHONOPY_BIN PHONOPY_INIT_BIN
    bash "$SCRIPTS/03_collect_force_sets.sh"
  fi
fi

# =============================================================================
# Step 5 — thermal properties → thermal_properties.yaml (+ results/ copies)
# =============================================================================
if should_run 5; then
  log "Step 5: thermal properties (mesh=$MESH  Tmax=$TMAX  dT=$TSTEP)"
  for s in "${STRUCTURES[@]}"; do
    [[ -f "$ROOT/$s/FORCE_SETS" || -f "$ROOT/$s/FORCE_CONSTANTS" ]] \
      || die "missing FORCE_SETS/FORCE_CONSTANTS in $s — run step 4 first (or drop --skip-fc)"
  done
  if ! resolve_phonopy_python; then
    die "no Python with phonopy module (need python3.13 or python3 + phonopy for thermal)"
  fi
  export MESH TMAX TSTEP PHONOPY_PYTHON
  # shellcheck disable=SC2086
  $PHONOPY_PYTHON "$SCRIPTS/run_phonopy_thermal.py" \
    --mesh $MESH --tmin 0 --tmax "$TMAX" --tstep "$TSTEP" \
    --copy-to "$RESULTS" \
    "$ROOT/nodef" "$ROOT/cVac" "$ROOT/2G"
  for s in "${STRUCTURES[@]}"; do
    [[ -f "$ROOT/$s/thermal_properties.yaml" ]] \
      || die "$s/thermal_properties.yaml was not written"
    zpe=$(awk '/zero_point_energy/ {print $2; exit}' "$ROOT/$s/thermal_properties.yaml")
    natom=$(awk '/^natom:/ {print $2; exit}' "$ROOT/$s/thermal_properties.yaml")
    echo "  $s: natom=$natom  ZPE=$zpe kJ/mol → results/thermal_properties_${s}.yaml"
  done
fi

# =============================================================================
# Step 6 — Schottky free energy, entropy, heat capacity vs T
# =============================================================================
if should_run 6; then
  log "Step 6: Schottky formation free energy, entropy, and Cv"

  for s in "${STRUCTURES[@]}"; do
    [[ -f "$ROOT/$s/thermal_properties.yaml" ]] \
      || die "missing $s/thermal_properties.yaml — run step 5 first (or --thermal-only)"
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

  # Fall back to results/static_energies[.example].dat when OUTCARs missing
  if [[ -z "$EDFT_NODEF" || -z "$EDFT_CVAC" || -z "$EDFT_2G" ]]; then
    read_static_energies_file
  fi

  py_args=(
    --nodef "$ROOT/nodef/thermal_properties.yaml"
    --cvac  "$ROOT/cVac/thermal_properties.yaml"
    --twog  "$ROOT/2G/thermal_properties.yaml"
    --out-dir "$RESULTS"
    --out   "$RESULTS/schottky.dat"
    --prefix schottky
  )

  if [[ -n "$EDFT_NODEF" && -n "$EDFT_CVAC" && -n "$EDFT_2G" ]]; then
    echo "  EDFT nodef=$EDFT_NODEF  cVac=$EDFT_CVAC  2G=$EDFT_2G  (eV)"
    py_args+=(--edft-nodef "$EDFT_NODEF" --edft-cvac "$EDFT_CVAC" --edft-2g "$EDFT_2G")
  else
    warn "Static TOTEN incomplete — vib-only table (pass EDFT_* , finish step 1, or results/static_energies.dat)"
  fi

  python3 "$SCRIPTS/schottky_from_thermal.py" "${py_args[@]}"

  log "Finished. Data tables:"
  echo "  $RESULTS/schottky_free_energy.dat"
  echo "  $RESULTS/schottky_entropy.dat"
  echo "  $RESULTS/schottky_heat_capacity.dat"
  echo "  $RESULTS/schottky.dat  (combined)"
  ls -la \
    "$RESULTS/schottky_free_energy.dat" \
    "$RESULTS/schottky_entropy.dat" \
    "$RESULTS/schottky_heat_capacity.dat" \
    "$RESULTS/schottky.dat" 2>/dev/null || true
  echo
  echo "---- free energy (head) ----"
  head -8 "$RESULTS/schottky_free_energy.dat" || true
  echo "---- entropy (head) ----"
  head -6 "$RESULTS/schottky_entropy.dat" || true
  echo "---- heat capacity (head) ----"
  head -6 "$RESULTS/schottky_heat_capacity.dat" || true

  # PDFs: F, S, Cv separately + combined three-panel figure
  plot_py=""
  if [[ "$SKIP_PLOT" -eq 0 ]]; then
    log "Step 6b: plot Schottky F, S, Cv vs T → PDF"
    plot_py=python3
    if python3.13 -c "import matplotlib" >/dev/null 2>&1; then
      plot_py=python3.13
    elif ! python3 -c "import matplotlib" >/dev/null 2>&1; then
      warn "matplotlib not found — skip PDF plots (install: python3 -m pip install --user matplotlib)"
      plot_py=""
    fi
    if [[ -n "$plot_py" ]]; then
      $plot_py "$SCRIPTS/plot_schottky.py" --results-dir "$RESULTS" --prefix schottky
      echo "  PDFs:"
      ls -la \
        "$RESULTS/schottky_free_energy.pdf" \
        "$RESULTS/schottky_entropy.pdf" \
        "$RESULTS/schottky_heat_capacity.pdf" \
        "$RESULTS/schottky_all.pdf" 2>/dev/null || true
    fi
  else
    warn "Schottky PDF plots skipped (--skip-plot)"
  fi

  # -------------------------------------------------------------------------
  # Step 6c — phonon band structure (bands.conf / bands.yaml / bands.pdf)
  # -------------------------------------------------------------------------
  if [[ "$SKIP_BANDS" -eq 1 ]]; then
    warn "Phonon bands skipped (--skip-bands)"
  else
    log "Step 6c: phonon band structure (BAND_POINTS=$BAND_POINTS)"
    for s in "${STRUCTURES[@]}"; do
      [[ -f "$ROOT/$s/FORCE_SETS" || -f "$ROOT/$s/FORCE_CONSTANTS" ]] \
        || die "missing FORCE_SETS/FORCE_CONSTANTS in $s — needed for bands"
    done
    if ! resolve_phonopy_python; then
      die "no Python with phonopy module (needed for band structure)"
    fi
    # shellcheck disable=SC2086
    $PHONOPY_PYTHON "$SCRIPTS/run_phonopy_bands.py" \
      --npoints "$BAND_POINTS" \
      --copy-to "$RESULTS" \
      "$ROOT/nodef" "$ROOT/cVac" "$ROOT/2G"

    for s in "${STRUCTURES[@]}"; do
      [[ -f "$ROOT/$s/bands.yaml" ]] || die "$s/bands.yaml was not written"
      [[ -f "$ROOT/$s/bands.conf" ]] || die "$s/bands.conf was not written"
      echo "  $s: bands.yaml + bands.conf OK"
    done

    if [[ "$SKIP_PLOT" -eq 0 ]]; then
      if [[ -z "$plot_py" ]]; then
        plot_py=python3
        if python3.13 -c "import matplotlib" >/dev/null 2>&1; then
          plot_py=python3.13
        elif ! python3 -c "import matplotlib" >/dev/null 2>&1; then
          warn "matplotlib not found — skip bands.pdf"
          plot_py=""
        fi
      fi
      if [[ -n "$plot_py" ]]; then
        log "Step 6d: plot phonon bands → bands.pdf"
        $plot_py "$SCRIPTS/plot_bands.py" --results-dir "$RESULTS" \
          "$ROOT/nodef" "$ROOT/cVac" "$ROOT/2G"
        echo "  Band PDFs (nodef, cVac, 2G + combined):"
        ls -la \
          "$RESULTS/bands_nodef.pdf" \
          "$RESULTS/nodef_bands.pdf" \
          "$RESULTS/bands_cVac.pdf" \
          "$RESULTS/bands_2G.pdf" \
          "$RESULTS/bands.pdf" \
          "$RESULTS/bands_nodef.yaml" \
          "$RESULTS/bands_nodef.conf" 2>/dev/null || true

        # Schottky combination of bands: ω_S = ω_2G + ω_cVac - factor * ω_nodef
        log "Step 6e: Schottky phonon bands → bands_schottky.pdf"
        $plot_py "$SCRIPTS/schottky_bands.py" --results-dir "$RESULTS" \
          --nodef "$ROOT/nodef" --cvac "$ROOT/cVac" --twog "$ROOT/2G"
        ls -la \
          "$RESULTS/bands_schottky.pdf" \
          "$RESULTS/bands_schotcky.pdf" \
          "$RESULTS/bands_schottky.yaml" 2>/dev/null || true
      fi
    fi
  fi
fi

log "Workflow complete."
