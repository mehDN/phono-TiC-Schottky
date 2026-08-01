#!/usr/bin/env bash
# Submit / run every pending disp_*/ job under nodef, cVac, 2G.
#
# *** TARGET: metis.mse.kth.se  — do NOT run on leto ***
#
# Metis: local pool MAX_JOBS × NPROC cores, CPU pinning, o.dat logs, resume-safe
# SLURM: sbatch every r.sh (other clusters only)
#
# Run ON METIS from phono/:
#   ssh metis
#   cd /slask/mehdin/dynamics/phono
#   bash scripts/submit_all_structures.sh
#   MAX_JOBS=7 NPROC=8 bash scripts/submit_all_structures.sh
#   bash scripts/run_local_parallel.sh --status
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=cluster_env.sh
source "$ROOT/scripts/cluster_env.sh"

STRUCTURES=(nodef cVac 2G)

echo "======== submit all force jobs ========"
cluster_summary

for s in "${STRUCTURES[@]}"; do
  n=$(find "$ROOT/$s" -maxdepth 1 -type d -name 'disp_*' 2>/dev/null | wc -l)
  if [[ "$n" -eq 0 ]]; then
    echo "ERROR: no disp_* in $s/ — run: bash scripts/02_prepare_vasp_jobs.sh" >&2
    exit 1
  fi
done

if [[ "$RUN_MODE" == "wrong_host" ]] || is_leto_host; then
  echo "ERROR: refuse to submit phono VASP on Leto / wrong host." >&2
  echo "  Use Metis:  ssh metis && cd $ROOT && bash scripts/submit_all_structures.sh" >&2
  require_metis_host hard || exit 2
fi

if [[ "$RUN_MODE" == "metis" || "$RUN_MODE" == "local" ]]; then
  require_metis_host hard || exit 2
  echo "Metis pool: MAX_JOBS=${MAX_JOBS} × NPROC=${NPROC} = ${TOTAL_CORES} cores  (host=$(cluster_hostname))"
  echo "Skipping completed (vasprun.xml). Resume-safe. Logs: disp_*/o.dat"
  exec bash "$ROOT/scripts/run_local_parallel.sh" "${STRUCTURES[@]}"
fi

if ! command -v sbatch >/dev/null 2>&1; then
  echo "ERROR: sbatch not found and RUN_MODE=${RUN_MODE}." >&2
  echo "  For Metis local pool: ssh metis && RUN_MODE=metis bash scripts/submit_all_structures.sh" >&2
  exit 1
fi

total=0
for s in "${STRUCTURES[@]}"; do
  if [[ ! -x "$ROOT/$s/submit_all.sh" ]]; then
    echo "ERROR: missing $s/submit_all.sh — run: bash scripts/02_prepare_vasp_jobs.sh" >&2
    exit 1
  fi
  n=$(find "$ROOT/$s" -maxdepth 1 -type d -name 'disp_*' | wc -l)
  echo "Submitting $n jobs in $s/ …"
  ( cd "$ROOT/$s" && ./submit_all.sh )
  total=$((total + n))
done

echo "Submitted ~$total force jobs."
echo "Monitor:  squeue -u \$USER"
echo "When all done:  bash run_workflow.sh --from 4"
