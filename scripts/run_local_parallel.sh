#!/usr/bin/env bash
# =============================================================================
# run_local_parallel.sh — batch-run phono disp_*/ (and static) VASP jobs on Metis
#
# *** RUN ON metis.mse.kth.se ONLY — do NOT run on leto ***
#
# Launch mechanics adapted from wc_114 scripts on shared /slask
# (run_leto.sh / inputs/r.sh), but the TARGET MACHINE is Metis.
#
# Default core budget (Metis, user cap 56):
#   MAX_JOBS=7 concurrent VASP calculations
#   NPROC=8   MPI ranks per calculation
#   Total     7 × 8 = 56 cores
#
# Optimum INCAR for NPROC=8:
#   NPAR=2  NSIM=4  OMP_NUM_THREADS=1
# Each concurrent job is pinned to a disjoint 8-core block
#   cores [CORE_BASE + slot*NPROC, … + NPROC-1]
#
# Usage (on Metis, from phono/):
#   ssh metis
#   cd /slask/mehdin/dynamics/phono
#   bash scripts/run_local_parallel.sh              # all structures
#   bash scripts/run_local_parallel.sh nodef cVac
#   bash scripts/run_local_parallel.sh --static
#   bash scripts/run_local_parallel.sh --status
#   bash scripts/run_local_parallel.sh --dry-run
#   nohup bash scripts/run_local_parallel.sh > results/local_runs/nohup.out 2>&1 &
#
# Env overrides:
#   MAX_JOBS=7 NPROC=8 NICE=19 CORE_BASE=0
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=cluster_env.sh
source "$ROOT/scripts/cluster_env.sh"

MODE="disp"          # disp | static
JOBS_FILE=""
STRUCTURES=()
DRY_RUN=0
FORCE=0
STATUS_ONLY=0

usage() {
  cat <<EOF
run_local_parallel.sh — Metis-only VASP pool (≤${TOTAL_CORES} cores)

  TARGET HOST: metis.mse.kth.se  (NOT leto)
  MAX_JOBS=${MAX_JOBS} × NPROC=${NPROC} = ${TOTAL_CORES} cores
  pin: CORE_BASE=${CORE_BASE} .. $((CORE_BASE + TOTAL_CORES - 1))

Usage (on Metis):
  bash scripts/run_local_parallel.sh [structures...]
  bash scripts/run_local_parallel.sh --static [structures...]
  bash scripts/run_local_parallel.sh --status | --dry-run | --force
  bash scripts/run_local_parallel.sh --jobs-file FILE

Environment:
  MAX_JOBS   concurrent VASP jobs (default 7 → 56 cores with NPROC=8)
  NPROC      MPI ranks per VASP (default 8)
  NICE       nice level (default 19)
  CORE_BASE  first pinned core (default 0)
  VASP       binary (default /prog/bin/vasp_std)
  FORCE_HOST=1  allow non-Metis (not recommended; still refuses Leto unless set)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --static) MODE=static; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --force)   FORCE=1; shift ;;
    --status)  STATUS_ONLY=1; shift ;;
    --max-jobs) MAX_JOBS="${2:?}"; TOTAL_CORES=$((MAX_JOBS * NPROC)); shift 2 ;;
    --nproc)    NPROC="${2:?}"; TOTAL_CORES=$((MAX_JOBS * NPROC)); shift 2 ;;
    --jobs-file)
      JOBS_FILE="${2:?--jobs-file needs a path}"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "ERROR: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      STRUCTURES+=("$1")
      shift
      ;;
  esac
done

if ((${#STRUCTURES[@]} == 0)); then
  STRUCTURES=(nodef cVac 2G)
fi

# Recompute after possible CLI overrides
TOTAL_CORES=$((MAX_JOBS * NPROC))
export MAX_JOBS NPROC TOTAL_CORES

LOG_DIR="${LOG_DIR:-$ROOT/results/local_runs}"
mkdir -p "$LOG_DIR"
MASTER_LOG="$LOG_DIR/parallel_$(date +%Y%m%d_%H%M%S).log"

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo "$msg"
  echo "$msg" >> "$MASTER_LOG"
}

# --- job state (phonopy forces: done = vasprun.xml present) -------------------
has_inputs() {
  local d="$1"
  [[ -f "${d}/INCAR" && -f "${d}/POSCAR" && -f "${d}/POTCAR" && -f "${d}/KPOINTS" ]]
}

is_done() {
  local d="$1"
  # Force calculations write vasprun.xml; also accept OUTCAR "accuracy" for static
  [[ -f "${d}/vasprun.xml" ]] && return 0
  if [[ -f "${d}/OUTCAR" ]] && grep -q "reached required accuracy" "${d}/OUTCAR" 2>/dev/null; then
    return 0
  fi
  return 1
}

needs_run() {
  local d="$1"
  has_inputs "$d" || return 1
  if (( FORCE )); then
    return 0
  fi
  if is_done "$d"; then
    return 1
  fi
  return 0
}

# --- collect job directories -------------------------------------------------
JOBS=()
if [[ -n "$JOBS_FILE" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    JOBS+=("$line")
  done < "$JOBS_FILE"
elif [[ "$MODE" == "static" ]]; then
  for s in "${STRUCTURES[@]}"; do
    d="$ROOT/$s/static"
    [[ -d "$d" ]] || continue
    JOBS+=("$d")
  done
else
  for s in "${STRUCTURES[@]}"; do
    shopt -s nullglob
    mapfile -t _ds < <(printf '%s\n' "$ROOT/$s"/disp_*/ | sort)
    shopt -u nullglob
    for d in "${_ds[@]+"${_ds[@]}"}"; do
      d="${d%/}"
      [[ -d "$d" ]] || continue
      JOBS+=("$d")
    done
  done
fi

PENDING=()
SKIPPED=0
BAD=0
for d in "${JOBS[@]+"${JOBS[@]}"}"; do
  if ! has_inputs "$d"; then
    ((BAD++)) || true
    continue
  fi
  if needs_run "$d"; then
    PENDING+=("$d")
  else
    ((SKIPPED++)) || true
  fi
done

status_report() {
  local running_vasp=0 est_jobs=0
  if command -v pgrep >/dev/null 2>&1; then
    running_vasp=$(pgrep -u "$(id -un)" -c vasp_std 2>/dev/null || true)
    running_vasp=${running_vasp:-0}
  fi
  if (( NPROC > 0 && running_vasp > 0 )); then
    est_jobs=$(( (running_vasp + NPROC - 1) / NPROC ))
  fi
  echo "Root     : ${ROOT}"
  echo "Mode     : ${MODE}  structures: ${STRUCTURES[*]}"
  echo "Folders  : ${#JOBS[@]}"
  echo "Done     : ${SKIPPED}"
  echo "Pending  : ${#PENDING[@]}"
  echo "Bad/miss : ${BAD}"
  echo "Live VASP processes (user): ${running_vasp}  (~${est_jobs} jobs × ${NPROC} ranks)"
  echo "Config   : MAX_JOBS=${MAX_JOBS}  NPROC=${NPROC}  total_cores=${TOTAL_CORES}  CORE_BASE=${CORE_BASE}"
}

if (( STATUS_ONLY )); then
  status_report
  exit 0
fi

if (( DRY_RUN )); then
  echo "Dry-run — would launch ${#PENDING[@]} jobs (${MAX_JOBS} at a time, ${NPROC} ranks each = ${TOTAL_CORES} cores):"
  echo "Already done/skipped: ${SKIPPED}"
  for d in "${PENDING[@]+"${PENDING[@]}"}"; do
    echo "  ${d#"$ROOT"/}"
  done
  exit 0
fi

# --- host: Metis only (not Leto) ---------------------------------------------
# --status / --dry-run still work off-host for inspection; real launches must
# be on metis.mse.kth.se.
if ! is_metis_host; then
  if is_leto_host; then
    echo "ERROR: refusing to launch VASP on Leto." >&2
    echo "  This phono workflow runs on Metis only:  ssh metis" >&2
    echo "  Then:  cd ${ROOT} && bash scripts/run_local_parallel.sh ..." >&2
    [[ "${FORCE_HOST:-0}" == "1" ]] || exit 2
    echo "WARNING: FORCE_HOST=1 — overriding Leto block (not recommended)." >&2
  else
    require_metis_host hard || exit 2
  fi
fi

HOST="$(hostname -s 2>/dev/null || hostname)"

if [[ ! -x "${VASP}" && ! -f "${VASP}" ]]; then
  echo "ERROR: VASP binary not found: ${VASP}" >&2
  exit 1
fi

: >> "${MASTER_LOG}"

# --- MPI environment (Metis oneAPI + pinning) --------------------------------
# Preserve ROOT — oneAPI CCL may export WORK_DIR and other globals.
_root_save="$ROOT"
source_oneapi || true
ROOT="$_root_save"
unset _root_save

if ! command -v mpirun >/dev/null 2>&1; then
  echo "ERROR: mpirun not found after sourcing ${ONEAPI_SETVARS:-<none>}." >&2
  echo "  On Metis, Intel MPI comes from oneAPI (/opt/intel/oneapi/setvars.sh)." >&2
  exit 1
fi
export OMP_NUM_THREADS=1
export I_MPI_PIN=1
export I_MPI_FABRICS="${I_MPI_FABRICS:-shm:ofi}"
export I_MPI_HYDRA_BOOTSTRAP="${I_MPI_HYDRA_BOOTSTRAP:-fork}"

log "============================================================"
log "Metis VASP batch  host=${HOST}  TARGET=metis (not leto)"
log "Jobs pending: ${#PENDING[@]}  already done/skipped: ${SKIPPED}  total: ${#JOBS[@]}"
log "Parallel: MAX_JOBS=${MAX_JOBS} × NPROC=${NPROC} = ${TOTAL_CORES} cores  (CORE_BASE=${CORE_BASE})"
log "VASP: ${VASP}"
log "Master log: ${MASTER_LOG}"
log "============================================================"

if ((${#PENDING[@]} == 0)); then
  log "Nothing to run."
  status_report
  exit 0
fi

# Slot map: PID → slot index (cores CORE_BASE+slot*NPROC …)
declare -A PID_SLOT=()
declare -A PID_DIR=()

reap_finished() {
  local pid dir base
  for pid in "${!PID_SLOT[@]}"; do
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid" 2>/dev/null || true
      dir="${PID_DIR[$pid]:-}"
      base="${dir#"$ROOT"/}"
      if [[ -n "$dir" ]] && is_done "$dir"; then
        log "DONE  ${base}"
      else
        log "FAIL  ${base:-pid=$pid}  (see ${dir:-?}/o.dat)"
      fi
      unset "PID_SLOT[$pid]"
      unset "PID_DIR[$pid]"
    fi
  done
}

wait_for_slot() {
  while (( ${#PID_SLOT[@]} >= MAX_JOBS )); do
    wait -n 2>/dev/null || true
    reap_finished
    if (( ${#PID_SLOT[@]} >= MAX_JOBS )); then
      sleep 1
      reap_finished
    fi
  done
}

next_slot() {
  local -A taken=()
  local pid cand
  for pid in "${!PID_SLOT[@]}"; do
    taken["${PID_SLOT[$pid]}"]=1
  done
  for ((cand = 0; cand < MAX_JOBS; cand++)); do
    if [[ -z "${taken[$cand]+x}" ]]; then
      echo "$cand"
      return 0
    fi
  done
  echo "0"
}

# Launch one job in-dir (foreground inside subshell); log → o.dat like wc_114
run_one() {
  local dir="$1"
  local slot="$2"
  local c0=$(( CORE_BASE + slot * NPROC ))
  local c1=$(( c0 + NPROC - 1 ))
  local pin_list="${c0}-${c1}"
  local job_log="${dir}/o.dat"
  local rc_file="${dir}/.vasp_exitcode"

  {
    echo "===== START $(date -Is) host=$(hostname) TARGET=metis slot=${slot} cores=${pin_list} np=${NPROC} ====="
    # CPU pinning so concurrent Metis jobs use disjoint core blocks
    if nice -n "${NICE}" mpirun -np "${NPROC}" \
        -genv OMP_NUM_THREADS 1 \
        -genv I_MPI_PIN 1 \
        -genv I_MPI_PIN_PROCESSOR_LIST "${pin_list}" \
        "${VASP}"; then
      echo 0 > "${rc_file}"
      echo "===== END   $(date -Is) OK ====="
    else
      local rc=$?
      echo "${rc}" > "${rc_file}"
      echo "===== END   $(date -Is) FAIL rc=${rc} ====="
    fi
  } >> "${job_log}" 2>&1
}

# --- launch loop -------------------------------------------------------------
launched=0
for d in "${PENDING[@]}"; do
  wait_for_slot
  slot="$(next_slot)"
  name="${d#"$ROOT"/}"
  log "LAUNCH [$((launched + 1))/${#PENDING[@]}] ${name}  slot=${slot}  cores=$((CORE_BASE + slot * NPROC))-$((CORE_BASE + slot * NPROC + NPROC - 1))"
  (
    cd "$d" || exit 1
    run_one "$d" "$slot"
  ) &
  pid=$!
  PID_SLOT[$pid]=$slot
  PID_DIR[$pid]=$d
  ((launched++)) || true
done

log "All ${launched} jobs submitted; waiting for remaining workers..."
for pid in "${!PID_SLOT[@]}"; do
  wait "$pid" 2>/dev/null || true
  unset "PID_SLOT[$pid]"
done
wait || true

# --- summary -----------------------------------------------------------------
ok=0
fail=0
still=0
for d in "${PENDING[@]}"; do
  name="${d#"$ROOT"/}"
  if is_done "$d"; then
    ((ok++)) || true
  elif [[ -f "${d}/.vasp_exitcode" ]] && [[ "$(cat "${d}/.vasp_exitcode")" != "0" ]]; then
    log "FAIL  ${name}  exit=$(cat "${d}/.vasp_exitcode")"
    ((fail++)) || true
  else
    log "INCOMPLETE ${name}"
    ((still++)) || true
  fi
done

log "============================================================"
log "Finished: done=${ok}  fail=${fail}  incomplete=${still}  skipped_earlier=${SKIPPED}"
log "Master log: ${MASTER_LOG}"
log "============================================================"
status_report

if (( fail + still > 0 )); then
  exit 2
fi
exit 0
