#!/usr/bin/env bash
# Shared cluster / host settings for the phonopy + VASP workflow.
# Sourced by prepare/submit scripts and run_workflow.sh.
#
# *** TARGET HOST: metis.mse.kth.se  (NOT leto) ***
# Launch mechanics are adapted from the wc_114 batch scripts that live on
# shared /slask (run_leto.sh / inputs/r.sh), but THIS phono pipeline is meant
# to execute on Metis only (56-core self-cap on the EPYC 9654 machine).
#
#   source /opt/intel/oneapi/setvars.sh
#   nice -n 19 mpirun -np 8 -genv OMP_NUM_THREADS 1 /prog/bin/vasp_std
#
# Default core budget on Metis: MAX_JOBS=7 × NPROC=8 = 56 cores
#
# Override examples (run ON metis):
#   MAX_JOBS=7 NPROC=8 ./run_workflow.sh --auto-submit
#   NPROC=4 MAX_JOBS=14 bash scripts/submit_all_structures.sh
#   RUN_MODE=slurm ACCOUNT=myalloc NTASKS=32 ./run_workflow.sh --auto-submit

# Current short hostname (lowercase)
cluster_hostname() {
  local h
  h="$(hostname -s 2>/dev/null || hostname || true)"
  printf '%s\n' "${h,,}"
}

# True if we are on metis.mse.kth.se (or hostname contains "metis")
is_metis_host() {
  local h
  h="$(cluster_hostname)"
  [[ "$h" == *metis* ]]
}

# True if we are on leto (wrong host for this pipeline)
is_leto_host() {
  local h
  h="$(cluster_hostname)"
  [[ "$h" == *leto* ]]
}

# Refuse Leto / non-Metis for local VASP pools. Override only with FORCE_HOST=1.
# Usage: require_metis_host   or   require_metis_host soft   (warn only)
require_metis_host() {
  local mode="${1:-hard}"   # hard | soft
  local h
  h="$(cluster_hostname)"

  if is_metis_host; then
    return 0
  fi

  if is_leto_host; then
    echo "ERROR: this phono pipeline must run on Metis, not Leto." >&2
    echo "  hostname = ${h}" >&2
    echo "  Correct:  ssh metis   (or  ssh metis.mse.kth.se)" >&2
    echo "  Then:     cd /slask/mehdin/dynamics/phono && bash scripts/submit_all_structures.sh" >&2
    echo "  (wc_114/run_leto.sh is a separate project for Leto; do not reuse its host here.)" >&2
    if [[ "${FORCE_HOST:-0}" == "1" ]]; then
      echo "WARNING: FORCE_HOST=1 — continuing on Leto anyway (not recommended)." >&2
      return 0
    fi
    [[ "$mode" == "soft" ]] && return 1
    return 2
  fi

  echo "WARNING: hostname is '${h}', expected metis (metis.mse.kth.se)." >&2
  echo "  This VASP pool is configured for Metis (≤56 cores). Do not run it on Leto." >&2
  if [[ "${FORCE_HOST:-0}" == "1" ]]; then
    echo "WARNING: FORCE_HOST=1 — continuing on ${h}." >&2
    return 0
  fi
  if [[ "$mode" == "soft" ]]; then
    return 1
  fi
  if [[ -t 0 ]]; then
    read -r -p "Continue on ${h} anyway (NOT Metis)? [y/N] " ans || true
    [[ "${ans}" =~ ^[Yy]$ ]] && return 0
  else
    echo "Non-interactive session: aborting (FORCE_HOST=1 to override)." >&2
  fi
  return 2
}

# ---------- detect run mode ----------
if [[ -z "${RUN_MODE:-}" ]]; then
  if is_metis_host; then
    RUN_MODE=metis
  elif is_leto_host; then
    # Do NOT treat Leto as a valid local-VASP target for phono
    RUN_MODE=wrong_host
  elif command -v sbatch >/dev/null 2>&1; then
    RUN_MODE=slurm
  else
    RUN_MODE=local
  fi
fi
export RUN_MODE

# ---------- Metis / local defaults (mirror wc_114 naming) ----------
# Accept both wc_114 names and older aliases.
export NPROC="${NPROC:-${CORES_PER_JOB:-8}}"
export CORES_PER_JOB="${CORES_PER_JOB:-$NPROC}"   # alias kept for older docs

export MAX_CORES="${MAX_CORES:-56}"
# MAX_JOBS = concurrent VASP instances (wc_114 name)
if [[ -n "${MAX_JOBS:-}" ]]; then
  :
elif [[ -n "${MAX_ACTIVE_JOBS:-}" ]]; then
  MAX_JOBS="${MAX_ACTIVE_JOBS}"
else
  MAX_JOBS=$((MAX_CORES / NPROC))
fi
if (( MAX_JOBS < 1 )); then
  MAX_JOBS=1
fi
export MAX_JOBS
export MAX_ACTIVE_JOBS="${MAX_ACTIVE_JOBS:-$MAX_JOBS}"   # alias

export TOTAL_CORES=$((MAX_JOBS * NPROC))
export NICE="${NICE:-${NICE_N:-19}}"
export NICE_N="${NICE_N:-$NICE}"
export CORE_BASE="${CORE_BASE:-0}"   # first core of reserved block (pin 0..TOTAL_CORES-1)

export VASP="${VASP:-${VASP_BIN:-/prog/bin/vasp_std}}"
export VASP_BIN="${VASP_BIN:-$VASP}"
export ONEAPI_SETVARS="${ONEAPI_SETVARS:-/opt/intel/oneapi/setvars.sh}"
export MPIRUN="${MPIRUN:-mpirun}"
export OMP_NUM_THREADS="${OMP_NUM_THREADS:-1}"

# VASP parallel over bands (wc_114 optimum for NPROC=8: NPAR=2 → NCORE=4)
# NPAR * NCORE ≈ NPROC (single-node). Prefer NPAR ≈ sqrt(NPROC).
if [[ -z "${NPAR:-}" ]]; then
  if   (( NPROC >= 16 )); then NPAR=4
  elif (( NPROC >= 8  )); then NPAR=2
  elif (( NPROC >= 4  )); then NPAR=2
  else NPAR=1
  fi
fi
export NPAR
export NSIM="${NSIM:-4}"
# NCORE for templates that still mention it (NCORE = NPROC/NPAR when divisible)
if [[ -z "${NCORE:-}" ]]; then
  if (( NPAR > 0 && NPROC % NPAR == 0 )); then
    NCORE=$((NPROC / NPAR))
  else
    NCORE=1
  fi
fi
export NCORE

# ---------- SLURM defaults (Tetralith / PDC / etc.) ----------
export ACCOUNT="${ACCOUNT:-naiss2023-5-84}"
export NODES="${NODES:-1}"
export NTASKS="${NTASKS:-${NPROC}}"
export WALLTIME="${WALLTIME:-12:00:00}"
export PARTITION="${PARTITION:-}"
export MODULE_LOAD="${MODULE_LOAD:-module add VASP/5.4.4.16052018-nsc1-intel-2018a-eb}"
export VASP_CMD="${VASP_CMD:-mpprun vasp}"
export STATIC_WALLTIME="${STATIC_WALLTIME:-04:00:00}"

cluster_summary() {
  local h
  h="$(cluster_hostname)"
  echo "  hostname=${h}  RUN_MODE=${RUN_MODE}"
  if is_leto_host; then
    echo "  *** WRONG HOST: Leto — use Metis (ssh metis) for this phono pipeline ***"
  fi
  if [[ "${RUN_MODE}" == "metis" || "${RUN_MODE}" == "local" ]]; then
    echo "  TARGET: Metis only (not Leto). Pattern adapted from wc_114 scripts on /slask."
    echo "  Pool: MAX_JOBS=${MAX_JOBS} × NPROC=${NPROC} = ${TOTAL_CORES} cores  (cap ${MAX_CORES})"
    echo "  CORE_BASE=${CORE_BASE}  pin cores ${CORE_BASE}–$((CORE_BASE + TOTAL_CORES - 1))"
    echo "  VASP=${VASP}  NPAR=${NPAR}  NSIM=${NSIM}  NICE=${NICE}"
  elif [[ "${RUN_MODE}" == "wrong_host" ]]; then
    echo "  Refuse local VASP on this host. ssh metis and re-run."
  else
    echo "  SLURM: ACCOUNT=${ACCOUNT}  NODES=${NODES}  NTASKS=${NTASKS}  WALLTIME=${WALLTIME}"
    [[ -n "${PARTITION}" ]] && echo "  PARTITION=${PARTITION}"
  fi
}

# Source oneAPI the same way as the Metis/wc_114 local launchers (set -u safe).
source_oneapi() {
  if [[ ! -f "${ONEAPI_SETVARS}" ]]; then
    return 1
  fi
  # oneAPI setvars.sh expands optional vars; under set -u that aborts.
  set +u
  if [[ ! -d "${HOME:-}" || ! -w "${HOME:-}" ]]; then
    export HOME="${TMPDIR:-/tmp}"
  fi
  # shellcheck disable=SC1090
  source "${ONEAPI_SETVARS}" >/dev/null 2>&1 || true
  set -u
  return 0
}
