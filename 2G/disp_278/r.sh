#!/bin/bash
# Single-folder VASP launcher — Metis only (metis.mse.kth.se), NOT Leto.
# 8 MPI ranks. Prefer the batch driver for many folders:
#   ssh metis
#   cd /slask/mehdin/dynamics/phono
#   bash scripts/run_local_parallel.sh
#   bash scripts/submit_all_structures.sh
#
# Usage (ON METIS, from a job folder):  bash r.sh

# Refuse accidental launch on Leto
_hn=$(hostname -s 2>/dev/null || hostname)
case "${_hn,,}" in
  *leto*)
    echo "ERROR: this r.sh is for Metis, not Leto (host=${_hn})." >&2
    echo "  ssh metis && cd /slask/mehdin/dynamics/phono && bash scripts/submit_all_structures.sh" >&2
    exit 2
    ;;
  *metis*) ;;
  *)
    echo "WARNING: host=${_hn} (expected metis). Continuing..." >&2
    ;;
esac

source /opt/intel/oneapi/setvars.sh >/dev/null 2>&1 || true
export OMP_NUM_THREADS=1

nohup nice -n 19 mpirun -np 8 \
  -genv OMP_NUM_THREADS 1 \
  /prog/bin/vasp_std >> o.dat 2>&1 &
