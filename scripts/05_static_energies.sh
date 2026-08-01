#!/usr/bin/env bash
# Stage static single-point DFT jobs (electronic Schottky term).
# Run these on the *relaxed* POSCARs (not displacements).
#
# Metis-only r.sh (not Leto). Batch run on metis.mse.kth.se with:
#   bash scripts/run_local_parallel.sh --static
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=cluster_env.sh
source "$ROOT/scripts/cluster_env.sh"

STRUCTURES=(nodef cVac 2G)

echo "======== stage static energy jobs ========"
cluster_summary

inject_parallel_incar() {
  local incar="$1"
  if grep -q '# Parallel (set by 0[25]_' "$incar" 2>/dev/null; then
    sed -i -E '/^[[:space:]]*(NPAR|NCORE|NSIM)[[:space:]]*=/d' "$incar"
    sed -i -E '/^# Parallel \(set by 0[25]_/d' "$incar"
  fi
  printf '\n# Parallel (set by 05_static_energies.sh for NPROC=%s; wc_114 style)\nNPAR   = %s\nNSIM   = %s\n' \
    "$NPROC" "$NPAR" "$NSIM" >> "$incar"
}

for s in "${STRUCTURES[@]}"; do
  echo "======== static energy job: $s ========"
  job="$ROOT/$s/static"
  mkdir -p "$job"
  cp "$ROOT/$s/POSCAR"               "$job/POSCAR"
  cp "$ROOT/$s/POTCAR"               "$job/POTCAR"
  cp "$ROOT/templates/INCAR.static"  "$job/INCAR"
  cp "$ROOT/templates/KPOINTS"       "$job/KPOINTS"
  inject_parallel_incar "$job/INCAR"

  if [[ "$RUN_MODE" == "metis" || "$RUN_MODE" == "local" ]]; then
    cat > "$job/r.sh" <<EOF
#!/bin/bash
# Static VASP launcher — Metis only (metis.mse.kth.se), NOT Leto.
# Prefer:  ssh metis && cd ${ROOT} && bash scripts/run_local_parallel.sh --static
#
# Usage (ON METIS, from this folder):  bash r.sh

_hn=\$(hostname -s 2>/dev/null || hostname)
case "\${_hn,,}" in
  *leto*)
    echo "ERROR: this r.sh is for Metis, not Leto (host=\${_hn})." >&2
    exit 2
    ;;
esac

source ${ONEAPI_SETVARS} >/dev/null 2>&1 || true
export OMP_NUM_THREADS=1

nohup nice -n ${NICE} mpirun -np ${NPROC} \\
  -genv OMP_NUM_THREADS 1 \\
  ${VASP} >> o.dat 2>&1 &
EOF
    chmod +x "$job/r.sh"
    echo "  -> $job  (local: bash scripts/run_local_parallel.sh --static)"
  else
    part_line=""
    if [[ -n "${PARTITION}" ]]; then
      part_line="#SBATCH --partition=${PARTITION}"
    fi
    cat > "$job/r.sh" <<EOF
#!/bin/bash
#SBATCH -A ${ACCOUNT}
#SBATCH -J st_${s}
#SBATCH -N ${NODES}
#SBATCH --ntasks-per-node=${NTASKS}
#SBATCH --cpus-per-task=1
#SBATCH -t ${STATIC_WALLTIME}
#SBATCH -o slurm-%j.out
${part_line}

export OMP_NUM_THREADS=1
${MODULE_LOAD}
${VASP_CMD}
EOF
    chmod +x "$job/r.sh"
    echo "  -> $job  (sbatch r.sh)"
  fi
done

echo
echo "After jobs finish, extract TOTEN:"
echo "  for s in nodef cVac 2G; do"
echo "    grep 'free  energy   TOTEN' \$s/static/OUTCAR | tail -1"
echo "  done"
