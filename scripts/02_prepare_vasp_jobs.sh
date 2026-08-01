#!/usr/bin/env bash
# Build one VASP job directory per displacement: disp_001, disp_002, ...
# Does not submit jobs; only stages inputs + r.sh launcher.
#
# Host-aware (see scripts/cluster_env.sh):
#   Metis/local: r.sh matches wc_114/inputs/r.sh (mpirun -np NPROC vasp_std)
#   SLURM:       #SBATCH + module load + mpprun/srun
#
# Prefer the batch driver for many folders:
#   bash scripts/run_local_parallel.sh
#   bash scripts/submit_all_structures.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=cluster_env.sh
source "$ROOT/scripts/cluster_env.sh"

STRUCTURES=(nodef cVac 2G)

echo "======== prepare VASP force jobs ========"
cluster_summary

# Inject NPAR/NSIM (wc_114 optimum) into staged INCAR
inject_parallel_incar() {
  local incar="$1"
  # Remove prior auto-injected block (idempotent re-prepare)
  if grep -q '# Parallel (set by 0[25]_' "$incar" 2>/dev/null; then
    # drop from that comment to EOF then re-append — safer: strip NPAR/NCORE/NSIM lines
    sed -i -E '/^[[:space:]]*(NPAR|NCORE|NSIM)[[:space:]]*=/d' "$incar"
    sed -i -E '/^# Parallel \(set by 0[25]_/d' "$incar"
  fi
  printf '\n# Parallel (set by 02_prepare_vasp_jobs.sh for NPROC=%s; wc_114 style)\nNPAR   = %s\nNSIM   = %s\n' \
    "$NPROC" "$NPAR" "$NSIM" >> "$incar"
}

# Single-folder launcher for Metis only (shape adapted from wc_114/inputs/r.sh).
# Batch driver does not use this; it launches mpirun with core pinning.
write_r_sh_metis() {
  local jobdir="$1"
  cat > "$jobdir/r.sh" <<EOF
#!/bin/bash
# Single-folder VASP launcher — Metis only (metis.mse.kth.se), NOT Leto.
# ${NPROC} MPI ranks. Prefer the batch driver for many folders:
#   ssh metis
#   cd ${ROOT}
#   bash scripts/run_local_parallel.sh
#   bash scripts/submit_all_structures.sh
#
# Usage (ON METIS, from a job folder):  bash r.sh

# Refuse accidental launch on Leto
_hn=\$(hostname -s 2>/dev/null || hostname)
case "\${_hn,,}" in
  *leto*)
    echo "ERROR: this r.sh is for Metis, not Leto (host=\${_hn})." >&2
    echo "  ssh metis && cd ${ROOT} && bash scripts/submit_all_structures.sh" >&2
    exit 2
    ;;
  *metis*) ;;
  *)
    echo "WARNING: host=\${_hn} (expected metis). Continuing..." >&2
    ;;
esac

source ${ONEAPI_SETVARS} >/dev/null 2>&1 || true
export OMP_NUM_THREADS=1

nohup nice -n ${NICE} mpirun -np ${NPROC} \\
  -genv OMP_NUM_THREADS 1 \\
  ${VASP} >> o.dat 2>&1 &
EOF
  chmod +x "$jobdir/r.sh"
}

write_r_sh_slurm() {
  local jobdir="$1"
  local label="$2"
  local part_line=""
  if [[ -n "${PARTITION}" ]]; then
    part_line="#SBATCH --partition=${PARTITION}"
  fi
  cat > "$jobdir/r.sh" <<EOF
#!/bin/bash
#SBATCH -A ${ACCOUNT}
#SBATCH -J ${label}
#SBATCH -N ${NODES}
#SBATCH --ntasks-per-node=${NTASKS}
#SBATCH --cpus-per-task=1
#SBATCH -t ${WALLTIME}
#SBATCH -o slurm-%j.out
${part_line}

export OMP_NUM_THREADS=1
export I_MPI_ADJUST_REDUCE=3
${MODULE_LOAD}
${VASP_CMD}
EOF
  chmod +x "$jobdir/r.sh"
}

for s in "${STRUCTURES[@]}"; do
  echo "======== prepare VASP jobs: $s ========"
  cd "$ROOT/$s"
  if [[ ! -f POTCAR ]]; then
    echo "ERROR: $s/POTCAR missing" >&2
    exit 1
  fi
  shopt -s nullglob
  poscars=(POSCAR-[0-9]*)
  shopt -u nullglob
  if (( ${#poscars[@]} == 0 )); then
    echo "ERROR: no POSCAR-* in $s — run 01_create_displacements.sh first" >&2
    exit 1
  fi

  for p in "${poscars[@]}"; do
    idx="${p#POSCAR-}"
    jobdir="disp_${idx}"
    mkdir -p "$jobdir"
    cp "$p"               "$jobdir/POSCAR"
    cp POTCAR             "$jobdir/POTCAR"
    cp "$ROOT/templates/INCAR.forces" "$jobdir/INCAR"
    cp "$ROOT/templates/KPOINTS"      "$jobdir/KPOINTS"
    inject_parallel_incar "$jobdir/INCAR"

    if [[ "$RUN_MODE" == "metis" || "$RUN_MODE" == "local" ]]; then
      write_r_sh_metis "$jobdir"
    else
      write_r_sh_slurm "$jobdir" "ph_${s}_${idx}"
    fi
  done

  if [[ "$RUN_MODE" == "metis" || "$RUN_MODE" == "local" ]]; then
    cat > submit_all.sh <<EOF
#!/usr/bin/env bash
# Run all disp_* for this structure on Metis only (not Leto), core-capped.
set -euo pipefail
ROOT="\$(cd "\$(dirname "\$0")/.." && pwd)"
STRUCT="\$(basename "\$(pwd)")"
# shellcheck source=cluster_env.sh
source "\$ROOT/scripts/cluster_env.sh"
require_metis_host hard || exit 2
exec bash "\$ROOT/scripts/run_local_parallel.sh" "\$STRUCT"
EOF
  else
    cat > submit_all.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
for d in disp_*/; do
  ( cd "$d" && sbatch r.sh )
done
EOF
  fi
  chmod +x submit_all.sh
  echo "  -> ${#poscars[@]} jobs in $s/disp_*/  (submit with: cd $s && ./submit_all.sh)"
  cd "$ROOT"
done

echo "Done. After VASP finishes: bash scripts/03_collect_force_sets.sh"
if [[ "$RUN_MODE" == "metis" || "$RUN_MODE" == "local" ]]; then
  echo "Run ON METIS (not Leto):  bash scripts/submit_all_structures.sh   # ≤ ${TOTAL_CORES} cores"
  echo "  ssh metis && cd ${ROOT}"
fi
